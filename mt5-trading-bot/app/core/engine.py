"""Moteur de trading.

Volontairement sans dependance Qt : il tourne dans son propre thread et
communique par callbacks, ce qui le rend testable sans interface. L'adaptateur
Qt (app/ui/engine_bridge.py) se contente de retransformer ces callbacks en
signaux Qt.

Deroulement d'un cycle :
    1. rafraichir le compte, faire tourner la journee si la date a change
    2. verifier les coupe-circuits (perte du jour, drawdown)
    3. reconcilier les positions (detecter celles fermees par le serveur)
    4. gerer les positions ouvertes (point mort, stop suiveur)
    5. chercher une entree sur chaque symbole, une seule fois par bougie close
"""

from __future__ import annotations

import threading
import traceback
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from typing import Callable, Dict, List, Optional

import pandas as pd

from ..config import AppConfig
from . import indicators as ind
from .broker import TIMEFRAMES, BrokerError, MT5Broker, OrderResult
from .journal import Journal
from .models import (
    AccountSnapshot, EngineStats, PositionInfo, Side, Signal, SymbolSpec,
)
from .risk import RiskManager
from .simulator import SimulatedBroker
from .strategies import build_strategy

LogFn = Callable[[str, str, str, str], None]          # level, category, symbol, message
StatsFn = Callable[[EngineStats], None]
PositionsFn = Callable[[List[PositionInfo]], None]


class TradingEngine:
    """Boucle de trading. Une instance vit le temps d'une session."""

    def __init__(
        self,
        config: AppConfig,
        journal: Journal,
        on_log: Optional[LogFn] = None,
        on_stats: Optional[StatsFn] = None,
        on_positions: Optional[PositionsFn] = None,
    ):
        self.config = config
        self.journal = journal
        self._on_log = on_log or (lambda *a: None)
        self._on_stats = on_stats or (lambda s: None)
        self._on_positions = on_positions or (lambda p: None)

        self.broker = None
        self.risk = RiskManager(config.risk)
        self.strategy = build_strategy(config.strategy)

        self._thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()
        self._lock = threading.RLock()
        self._running = False

        self._stats = EngineStats()
        self._specs: Dict[str, SymbolSpec] = {}
        self._last_bar: Dict[str, datetime] = {}
        self._tracked: Dict[int, PositionInfo] = {}
        self._initial_risk: Dict[int, float] = {}
        self._last_atr: Dict[str, float] = {}
        self._session_start = datetime.now(timezone.utc)
        self._equity_log_at = datetime.min.replace(tzinfo=timezone.utc)
        self._pending_close_all = False
        self._pending_closes: List[int] = []

    # =================================================== cycle de vie =====
    @property
    def running(self) -> bool:
        return self._running

    def start(self) -> None:
        with self._lock:
            if self._running:
                return
            self._stop_event.clear()
            self._thread = threading.Thread(target=self._run, name="TradingEngine", daemon=True)
            self._running = True
            self._thread.start()

    def stop(self, timeout: float = 10.0) -> None:
        self._stop_event.set()
        thread = self._thread
        if thread is not None and thread.is_alive():
            thread.join(timeout=timeout)
        self._running = False

    def request_close_all(self) -> None:
        """Demande la fermeture de toutes les positions au prochain cycle."""
        self._pending_close_all = True

    def request_close(self, ticket: int) -> None:
        """Demande la fermeture d'une position precise au prochain cycle."""
        with self._lock:
            if ticket not in self._pending_closes:
                self._pending_closes.append(int(ticket))

    def request_halt(self, reason: str = "Arret manuel") -> None:
        self.risk.halted = True
        self.risk.halt_reason = reason

    def resume(self) -> None:
        """Leve l'arret manuel. Ne leve pas un arret du a un coupe-circuit."""
        self.risk.halted = False
        self.risk.halt_reason = ""

    # ------------------------------------------------------------- utils ----
    def log(self, level: str, category: str, message: str, symbol: str = "") -> None:
        try:
            self.journal.log(level, category, message, symbol)
        except Exception:
            pass  # un journal en echec ne doit jamais tuer le moteur
        self._on_log(level, category, symbol, message)

    def _emit_stats(self) -> None:
        self._on_stats(replace(self._stats))

    # ============================================================ boucle ====
    def _run(self) -> None:
        try:
            if not self._connect():
                return
            self._bootstrap()
            while not self._stop_event.is_set():
                started = datetime.now(timezone.utc)
                try:
                    self._cycle()
                    self._stats.last_error = ""
                except BrokerError as exc:
                    self._stats.last_error = str(exc)
                    self.log("ERROR", "broker", str(exc))
                except Exception as exc:  # un cycle rate ne doit pas arreter le bot
                    self._stats.last_error = f"{type(exc).__name__}: {exc}"
                    self.log("ERROR", "moteur", f"Erreur de cycle : {exc}")
                    self.log("DEBUG", "moteur", traceback.format_exc()[-1500:])
                self._emit_stats()
                elapsed = (datetime.now(timezone.utc) - started).total_seconds()
                self._stop_event.wait(max(0.2, self.config.trading.poll_seconds - elapsed))
        finally:
            self._shutdown()

    def _connect(self) -> bool:
        conn = self.config.connection
        self.broker = SimulatedBroker() if conn.offline_simulation else MT5Broker()
        try:
            ok, message = self.broker.connect(conn)
        except BrokerError as exc:
            self._stats.connected = False
            self._stats.last_error = str(exc)
            self.log("ERROR", "connexion", str(exc))
            self._running = False
            self._emit_stats()
            return False
        if not ok:
            self._stats.connected = False
            self._stats.last_error = message
            self.log("ERROR", "connexion", message)
            self._running = False
            self._emit_stats()
            return False

        account = self.broker.account()
        if account is None:
            self.log("ERROR", "connexion", "Impossible de lire les informations du compte.")
            self._running = False
            self._emit_stats()
            return False

        # Garde-fou : le type de compte annonce doit correspondre au vrai type.
        wants_real = conn.account_kind == "real"
        if wants_real and account.is_demo:
            self.log(
                "WARN", "connexion",
                "Compte REEL demande mais le terminal est connecte a un compte DEMO. "
                "Le bot continue sur le compte demo.",
            )
        if not wants_real and not account.is_demo:
            self.log(
                "ERROR", "connexion",
                "SECURITE : compte DEMO demande mais le terminal est connecte a un "
                "compte REEL. Le moteur refuse de demarrer. Changez le type de compte "
                "dans les parametres si c'est voulu.",
            )
            self.broker.shutdown()
            self._running = False
            self._stats.connected = False
            self._emit_stats()
            return False

        self._stats.connected = True
        self._stats.account = account
        self.log("INFO", "connexion", message)
        return True

    def _bootstrap(self) -> None:
        account = self.broker.account()
        now = self._now()
        self.risk.start_session(account, now)
        self._session_start = now
        self._stats.day_start_equity = self.risk.day_start_equity
        self._stats.peak_equity = self.risk.peak_equity
        self._stats.running = True
        self._stats.live_orders = self.config.trading.live_orders_enabled

        for symbol in self.config.trading.symbols:
            if not self.broker.ensure_symbol(symbol):
                self.log("WARN", "symbole", f"{symbol} introuvable chez le broker, ignore.", symbol)
                continue
            spec = self.broker.symbol_spec(symbol)
            if spec is None:
                self.log("WARN", "symbole", f"Specification indisponible pour {symbol}.", symbol)
                continue
            self._specs[symbol] = spec

        if not self._specs:
            self.log("ERROR", "symbole", "Aucun symbole utilisable. Verifiez le Market Watch.")

        mode = "ORDRES REELS ACTIFS" if self.config.trading.live_orders_enabled \
            else "mode analyse (aucun ordre envoye)"
        self.log("INFO", "moteur", f"Moteur demarre - {mode}. Symboles : "
                                   f"{', '.join(self._specs) or 'aucun'}")
        # Adopte les positions deja ouvertes portant notre magic number.
        for pos in self.broker.positions(self.config.trading.magic):
            self._tracked[pos.ticket] = pos
            if pos.sl:
                self._initial_risk[pos.ticket] = abs(pos.price_open - pos.sl)
        if self._tracked:
            self.log("INFO", "positions",
                     f"{len(self._tracked)} position(s) existante(s) reprise(s) en gestion.")

    def _shutdown(self) -> None:
        self._running = False
        self._stats.running = False
        self._stats.connected = False
        if self.broker is not None:
            try:
                self.broker.shutdown()
            except Exception:
                pass
        self.log("INFO", "moteur", "Moteur arrete.")
        self._emit_stats()

    def _now(self) -> datetime:
        try:
            return self.broker.server_time()
        except Exception:
            return datetime.now(timezone.utc)

    # ============================================================= cycle ====
    def _cycle(self) -> None:
        if getattr(self.broker, "is_simulated", False):
            # Fait avancer le marche fictif pour que la session soit vivante.
            self.broker.advance(5)

        account = self.broker.account()
        if account is None:
            raise BrokerError("Compte injoignable (terminal ferme ?)")
        now = self._now()

        self._stats.account = account
        self.risk.update_equity(account)
        if self.risk.roll_day_if_needed(account, now):
            self.log("INFO", "risque", "Nouvelle journee : compteurs journaliers remis a zero.")

        self._stats.day_start_equity = self.risk.day_start_equity
        self._stats.peak_equity = self.risk.peak_equity
        self._stats.drawdown_pct = self.risk.drawdown_pct(account)
        self._stats.trades_today = self.risk.trades_today
        self._stats.pnl_today = account.equity - self.risk.day_start_equity
        self._stats.last_cycle = now
        self._stats.live_orders = self.config.trading.live_orders_enabled

        self._reconcile_positions()
        positions = list(self._tracked.values())
        self._stats.open_positions = len(positions)
        self._on_positions(positions)

        if self._pending_close_all:
            self._pending_close_all = False
            self._close_all("demande manuelle")
            return

        if self._pending_closes:
            with self._lock:
                tickets, self._pending_closes = self._pending_closes, []
            for ticket in tickets:
                self._close_one(ticket, "demande manuelle")
            return

        halt = self.risk.check_circuit_breakers(account)
        self._stats.halted = self.risk.halted
        self._stats.halt_reason = self.risk.halt_reason
        if halt:
            if self.config.risk.close_all_on_daily_stop and self._tracked:
                self.log("WARN", "risque", f"{halt} - fermeture des positions ouvertes.")
                self._close_all("coupe-circuit")
            return

        self._manage_positions()
        self._look_for_entries(account, now)
        self._maybe_log_equity(account)

    def _maybe_log_equity(self, account: AccountSnapshot) -> None:
        now = datetime.now(timezone.utc)
        if (now - self._equity_log_at).total_seconds() >= 60:
            self._equity_log_at = now
            self.journal.record_equity(account.balance, account.equity)

    # ------------------------------------------------- suivi des positions --
    def _reconcile_positions(self) -> None:
        """Met a jour le cache de positions et journalise celles qui ont disparu."""
        current = {p.ticket: p for p in self.broker.positions(self.config.trading.magic)}
        closed = set(self._tracked) - set(current)
        if closed:
            deals = self.broker.closed_deals_since(
                self._session_start - timedelta(days=1), self.config.trading.magic
            )
            by_position: Dict[int, dict] = {}
            for d in deals:
                by_position.setdefault(d.get("position_id", d["ticket"]), d)
            for ticket in closed:
                old = self._tracked.pop(ticket, None)
                self._initial_risk.pop(ticket, None)
                deal = by_position.get(ticket)
                profit = deal["profit"] if deal else (old.profit if old else 0.0)
                price = deal["price"] if deal else (old.price_current if old else 0.0)
                reason = (deal or {}).get("comment") or "fermeture serveur"
                symbol = old.symbol if old else ""
                self.journal.record_close(ticket, price, profit, reason)
                verdict = "GAIN" if profit >= 0 else "PERTE"
                self.log(
                    "INFO" if profit >= 0 else "WARN", "position",
                    f"Position {ticket} {symbol} fermee - {verdict} "
                    f"{profit:+.2f} ({reason})",
                    symbol,
                )
        self._tracked = current

    def _manage_positions(self) -> None:
        """Point mort puis stop suiveur, sur les positions du bot uniquement."""
        cfg = self.config.risk
        for ticket, pos in list(self._tracked.items()):
            spec = self._specs.get(pos.symbol) or self.broker.symbol_spec(pos.symbol)
            if spec is None:
                continue
            risk = self._initial_risk.get(ticket)
            if risk is None or risk <= 0:
                risk = abs(pos.price_open - pos.sl) if pos.sl else 0.0
                if risk <= 0:
                    continue
                self._initial_risk[ticket] = risk

            gain = (pos.price_current - pos.price_open) * pos.side.sign
            r_multiple = gain / risk if risk > 0 else 0.0
            new_sl = pos.sl
            action = ""

            # 1. Point mort : securise le trade des qu'il a paye son risque.
            if cfg.breakeven_at_r > 0 and r_multiple >= cfg.breakeven_at_r:
                buffer = spec.point * 2
                be = pos.price_open + pos.side.sign * buffer
                if self._is_better_stop(pos.side, be, new_sl):
                    new_sl, action = be, "point mort"

            # 2. Stop suiveur a distance ATR.
            if cfg.trailing_start_r > 0 and r_multiple >= cfg.trailing_start_r:
                atr_value = self._last_atr.get(pos.symbol, 0.0)
                if atr_value > 0:
                    trail = pos.price_current - pos.side.sign * atr_value * cfg.trailing_atr_mult
                    if self._is_better_stop(pos.side, trail, new_sl):
                        new_sl, action = trail, "stop suiveur"

            if not action or new_sl == pos.sl:
                continue

            # Respecte la distance minimale imposee par le broker.
            min_dist = max(spec.stops_level, 0) * spec.point
            if min_dist > 0 and abs(pos.price_current - new_sl) < min_dist:
                continue
            new_sl = round(new_sl, spec.digits)
            if new_sl == round(pos.sl, spec.digits):
                continue

            if not self.config.trading.live_orders_enabled:
                self.log("INFO", "gestion",
                         f"[analyse] {action} sur {pos.symbol} #{ticket} : SL -> {new_sl}",
                         pos.symbol)
                continue
            result = self.broker.modify_position(ticket, new_sl, pos.tp)
            if result.ok:
                pos.sl = new_sl
                self.log("INFO", "gestion",
                         f"{action.capitalize()} sur {pos.symbol} #{ticket} : "
                         f"SL -> {new_sl} ({r_multiple:.2f}R)", pos.symbol)
            else:
                self.log("WARN", "gestion",
                         f"Echec {action} sur #{ticket} : {result.message}", pos.symbol)

    @staticmethod
    def _is_better_stop(side: Side, candidate: float, current: float) -> bool:
        """Un stop n'est deplace que dans le sens qui reduit le risque."""
        if not current:
            return True
        return candidate > current if side is Side.BUY else candidate < current

    def _close_one(self, ticket: int, why: str) -> None:
        pos = self._tracked.get(ticket)
        if pos is None:
            self.log("WARN", "position", f"Position #{ticket} deja fermee.")
            return
        if not self.config.trading.live_orders_enabled:
            self.log("INFO", "position",
                     f"[analyse] fermeture de #{ticket} {pos.symbol} ({why})", pos.symbol)
            return
        result = self.broker.close_position(ticket, self.config.trading.deviation_points)
        if result.ok:
            self.log("INFO", "position",
                     f"Position #{ticket} {pos.symbol} fermee ({why})", pos.symbol)
        else:
            self.log("ERROR", "position",
                     f"Echec de fermeture de #{ticket} : {result.message}", pos.symbol)

    def _close_all(self, why: str) -> None:
        for ticket, pos in list(self._tracked.items()):
            if not self.config.trading.live_orders_enabled:
                self.log("INFO", "position",
                         f"[analyse] fermeture de #{ticket} {pos.symbol} ({why})", pos.symbol)
                continue
            result = self.broker.close_position(ticket, self.config.trading.deviation_points)
            if result.ok:
                self.log("INFO", "position",
                         f"Position #{ticket} {pos.symbol} fermee ({why})", pos.symbol)
            else:
                self.log("ERROR", "position",
                         f"Echec de fermeture de #{ticket} : {result.message}", pos.symbol)

    # ------------------------------------------------------- recherche ------
    def _look_for_entries(self, account: AccountSnapshot, now: datetime) -> None:
        scfg = self.config.strategy
        open_ok, why = self.risk.session_open(now)
        if not open_ok:
            return

        bar_minutes = TIMEFRAMES.get(scfg.timeframe, 15)
        candidates: List[tuple[Signal, SymbolSpec, float]] = []

        for symbol, spec in self._specs.items():
            try:
                signal_data = self._analyse(symbol, spec)
            except Exception as exc:
                self.log("WARN", "analyse", f"Analyse impossible sur {symbol} : {exc}", symbol)
                continue
            if signal_data is None:
                continue
            signal, spread_points = signal_data

            if self.risk.in_cooldown(symbol, signal.bar_time, scfg.cooldown_bars, bar_minutes):
                self.log("DEBUG", "analyse",
                         f"{symbol} : signal ignore (temporisation apres le dernier trade).",
                         symbol)
                continue
            candidates.append((signal, spec, spread_points))

        # Quand plusieurs signaux tombent ensemble, on prend le mieux note :
        # le quota de positions est limite, autant le depenser sur le meilleur.
        candidates.sort(key=lambda c: c[0].confidence, reverse=True)
        for signal, spec, spread_points in candidates:
            self._try_enter(signal, spec, account, now, spread_points)

    def _analyse(self, symbol: str, spec: SymbolSpec) -> Optional[tuple[Signal, float]]:
        scfg = self.config.strategy
        need = max(scfg.bars, ind.required_bars(scfg))

        ltf = self.broker.rates(symbol, scfg.timeframe, need + 1)
        if ltf is None or len(ltf) < ind.required_bars(scfg):
            return None
        # La derniere bougie est en cours de formation : on la retire pour que
        # les signaux ne changent pas d'avis en cours de route.
        ltf = ltf.iloc[:-1]
        if ltf.empty:
            return None

        last_bar_time = ltf.index[-1].to_pydatetime()
        if self._last_bar.get(symbol) == last_bar_time:
            return None  # deja analyse cette bougie
        self._last_bar[symbol] = last_bar_time

        ltf = ind.enrich(ltf, scfg)
        self._last_atr[symbol] = float(ltf["atr"].iloc[-1]) if not pd.isna(ltf["atr"].iloc[-1]) else 0.0

        htf = None
        if scfg.higher_timeframe and scfg.higher_timeframe != scfg.timeframe:
            raw_htf = self.broker.rates(symbol, scfg.higher_timeframe, ind.required_bars(scfg) + 2)
            if raw_htf is not None and len(raw_htf) > 2:
                htf = ind.enrich(raw_htf.iloc[:-1], scfg)

        signal = self.strategy.generate(symbol, ltf, htf)
        if signal is None:
            return None

        tick = self.broker.tick(symbol)
        if tick is None:
            return None
        bid, ask, _ = tick
        spread_points = (ask - bid) / spec.point if spec.point > 0 else 0.0
        return signal, spread_points

    def _try_enter(
        self,
        signal: Signal,
        spec: SymbolSpec,
        account: AccountSnapshot,
        now: datetime,
        spread_points: float,
    ) -> None:
        tick = self.broker.tick(signal.symbol)
        if tick is None:
            return
        bid, ask, _ = tick
        entry_price = ask if signal.side is Side.BUY else bid

        normalized = self.risk.normalize_stops(signal, spec, entry_price)
        if normalized is None:
            return

        positions = list(self._tracked.values())
        decision = self.risk.evaluate(normalized, spec, account, positions, now, spread_points)
        header = (
            f"{signal.symbol} {signal.side.value} @ {normalized.entry} | "
            f"SL {normalized.stop_loss} TP {normalized.take_profit} | "
            f"R:R {normalized.rr:.2f} | confiance {signal.confidence:.0%}"
        )
        if not decision.approved:
            self.log("INFO", "signal",
                     f"Signal refuse - {header} | motif : {'; '.join(decision.reasons)}",
                     signal.symbol)
            return

        if not self.config.trading.live_orders_enabled:
            self.log("INFO", "signal",
                     f"[analyse] Signal valide - {header} | {decision.reasons[0]} | "
                     f"{signal.reason}", signal.symbol)
            return

        result: OrderResult = self.broker.send_market_order(
            symbol=signal.symbol,
            side=signal.side,
            volume=decision.volume,
            sl=normalized.stop_loss,
            tp=normalized.take_profit,
            magic=self.config.trading.magic,
            deviation=self.config.trading.deviation_points,
            comment=f"{self.config.strategy.name[:12]}",
        )
        if not result.ok:
            self.log("ERROR", "ordre",
                     f"Echec d'envoi - {header} | {result.message}", signal.symbol)
            return

        fill_price = result.price or normalized.entry
        self.risk.register_fill(signal.symbol, signal.bar_time)
        self._initial_risk[result.ticket] = abs(fill_price - normalized.stop_loss)

        # La position est inscrite tout de suite dans le cache, sans attendre la
        # reconciliation du prochain cycle : sinon, plusieurs signaux tombant sur
        # le meme cycle verraient tous "zero position ouverte" et depasseraient
        # les plafonds de positions simultanees.
        self._tracked[result.ticket] = PositionInfo(
            ticket=result.ticket,
            symbol=signal.symbol,
            side=signal.side,
            volume=decision.volume,
            price_open=fill_price,
            price_current=fill_price,
            sl=normalized.stop_loss,
            tp=normalized.take_profit,
            profit=0.0,
            swap=0.0,
            magic=self.config.trading.magic,
            comment=self.config.strategy.name,
            time_open=datetime.now(timezone.utc),
        )
        self._stats.open_positions = len(self._tracked)
        self.journal.record_open(
            ticket=result.ticket,
            symbol=signal.symbol,
            side=signal.side.value,
            volume=decision.volume,
            price_open=fill_price,
            sl=normalized.stop_loss,
            tp=normalized.take_profit,
            strategy=self.config.strategy.name,
            reason=signal.reason,
            confidence=signal.confidence,
            simulated=getattr(self.broker, "is_simulated", False),
        )
        self.log("INFO", "ordre",
                 f"ORDRE EXECUTE #{result.ticket} - {signal.symbol} {signal.side.value} "
                 f"{decision.volume} lot(s) @ {fill_price} | SL {normalized.stop_loss} "
                 f"TP {normalized.take_profit} | {signal.reason}", signal.symbol)

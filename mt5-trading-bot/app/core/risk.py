"""Gestion du risque : dimensionnement des positions et garde-fous.

C'est le module le plus important de l'application. Une strategie mediocre
avec une bonne gestion du risque survit ; une bonne strategie sans gestion du
risque finit par rendre le compte. Toutes les verifications sont faites avant
l'envoi de l'ordre et chacune peut refuser seule le trade.
"""

from __future__ import annotations

import math
from datetime import datetime, time as dtime, timezone
from typing import List, Optional

from ..config import RiskConfig
from .models import AccountSnapshot, PositionInfo, RiskDecision, Side, Signal, SymbolSpec

_WEEKDAY_FIELDS = (
    "trade_monday", "trade_tuesday", "trade_wednesday", "trade_thursday", "trade_friday",
)


def round_to_step(value: float, step: float) -> float:
    """Arrondit *vers le bas* au pas de volume du broker.

    Toujours vers le bas : arrondir au plus proche pourrait depasser le risque
    demande.
    """
    if step <= 0:
        return value
    steps = math.floor(round(value / step, 8))
    result = steps * step
    # Le pas est souvent 0.01 : on recale sur sa precision decimale pour eviter
    # les 0.12000000000000001 que le broker refuse.
    decimals = max(0, -int(math.floor(math.log10(step)))) if step < 1 else 0
    return round(result, decimals + 2)


class RiskManager:
    """Etat journalier + decisions. Une instance par session de trading."""

    def __init__(self, cfg: RiskConfig):
        self.cfg = cfg
        self.day_start_equity: float = 0.0
        self.peak_equity: float = 0.0
        self.trades_today: int = 0
        self.current_day: Optional[datetime.date] = None
        self.halted: bool = False
        self.halt_reason: str = ""
        self.last_entry_bar: dict[str, datetime] = {}

    # ------------------------------------------------------ cycle de vie ----
    def start_session(self, account: AccountSnapshot, now: datetime) -> None:
        self.current_day = now.date()
        self.day_start_equity = account.equity
        self.peak_equity = max(self.peak_equity, account.equity) or account.equity
        self.trades_today = 0
        self.halted = False
        self.halt_reason = ""

    def roll_day_if_needed(self, account: AccountSnapshot, now: datetime) -> bool:
        """Remet a zero les compteurs journaliers au changement de date.

        Le kill switch de drawdown global, lui, n'est pas remis a zero : il
        protege le capital sur toute la duree de vie du compte.
        """
        if self.current_day is not None and now.date() == self.current_day:
            return False
        self.current_day = now.date()
        self.day_start_equity = account.equity
        self.trades_today = 0
        if self.halt_reason.startswith("Perte journaliere"):
            self.halted = False
            self.halt_reason = ""
        return True

    def update_equity(self, account: AccountSnapshot) -> None:
        if account.equity > self.peak_equity:
            self.peak_equity = account.equity

    # ------------------------------------------------------------ mesures ----
    def daily_loss_pct(self, account: AccountSnapshot) -> float:
        if self.day_start_equity <= 0:
            return 0.0
        return (self.day_start_equity - account.equity) / self.day_start_equity * 100.0

    def drawdown_pct(self, account: AccountSnapshot) -> float:
        if self.peak_equity <= 0:
            return 0.0
        return max(0.0, (self.peak_equity - account.equity) / self.peak_equity * 100.0)

    def check_circuit_breakers(self, account: AccountSnapshot) -> Optional[str]:
        """Retourne la raison d'un arret d'urgence, ou None.

        Le drawdown maximal est definitif pour la session : il demande une
        intervention humaine, on ne redemarre pas tout seul apres l'avoir
        touche.
        """
        if self.halted:
            return self.halt_reason
        dd = self.drawdown_pct(account)
        if dd >= self.cfg.max_drawdown_pct > 0:
            self.halted = True
            self.halt_reason = (
                f"Drawdown maximal atteint : {dd:.2f}% >= {self.cfg.max_drawdown_pct:.2f}%"
            )
            return self.halt_reason
        daily = self.daily_loss_pct(account)
        if daily >= self.cfg.max_daily_loss_pct > 0:
            self.halted = True
            self.halt_reason = (
                f"Perte journaliere maximale atteinte : {daily:.2f}% "
                f">= {self.cfg.max_daily_loss_pct:.2f}%"
            )
            return self.halt_reason
        return None

    # ----------------------------------------------------------- horaires ----
    def session_open(self, now: datetime) -> tuple[bool, str]:
        weekday = now.weekday()  # 0 = lundi
        if weekday >= 5:
            return False, "Week-end : marche ferme"
        if not getattr(self.cfg, _WEEKDAY_FIELDS[weekday], True):
            jours = ("lundi", "mardi", "mercredi", "jeudi", "vendredi")
            return False, f"Trading desactive le {jours[weekday]}"
        hour = now.hour
        start, end = self.cfg.session_start_hour, self.cfg.session_end_hour
        if start <= end:
            inside = start <= hour < end
        else:  # session a cheval sur minuit
            inside = hour >= start or hour < end
        if not inside:
            return False, f"Hors session ({start}h-{end}h, il est {hour}h serveur)"
        if weekday == 4 and hour >= self.cfg.friday_cutoff_hour:
            return False, f"Vendredi apres {self.cfg.friday_cutoff_hour}h : plus d'entree"
        return True, ""

    # ------------------------------------------------- dimensionnement ----
    def normalize_stops(
        self, signal: Signal, spec: SymbolSpec, entry_price: float
    ) -> Optional[Signal]:
        """Reancre SL/TP sur le prix reel et respecte la distance minimale broker.

        Les distances (risque et objectif) issues de la strategie sont
        conservees, seul le point d'ancrage change. Si le broker impose une
        distance minimale superieure, on **elargit** le stop (jamais on ne le
        resserre) et on elargit l'objectif d'autant pour garder le meme R:R.
        """
        sl_dist = signal.risk_distance
        tp_dist = signal.reward_distance
        if sl_dist <= 0 or tp_dist <= 0:
            return None
        rr = tp_dist / sl_dist

        min_dist = max(spec.stops_level, 0) * spec.point
        if min_dist > 0:
            # marge de securite : le spread peut bouger entre le calcul et l'envoi
            min_dist *= 1.2
            if sl_dist < min_dist:
                sl_dist = min_dist
                tp_dist = sl_dist * rr
            if tp_dist < min_dist:
                tp_dist = min_dist

        sign = signal.side.sign
        digits = spec.digits
        return Signal(
            symbol=signal.symbol,
            side=signal.side,
            entry=round(entry_price, digits),
            stop_loss=round(entry_price - sign * sl_dist, digits),
            take_profit=round(entry_price + sign * tp_dist, digits),
            confidence=signal.confidence,
            reason=signal.reason,
            atr=signal.atr,
            bar_time=signal.bar_time,
        )

    def position_size(
        self, signal: Signal, spec: SymbolSpec, account: AccountSnapshot
    ) -> tuple[float, str]:
        """Volume qui fait perdre exactement `risk_per_trade_pct` si le SL saute.

        Retourne (volume, message d'erreur). Volume 0 => trade impossible.
        """
        risk_amount = account.equity * self.cfg.risk_per_trade_pct / 100.0
        if risk_amount <= 0:
            return 0.0, "Montant de risque nul (equity ou pourcentage a zero)"

        tick_size = spec.trade_tick_size or spec.point
        tick_value = spec.trade_tick_value
        if tick_size <= 0 or tick_value <= 0:
            return 0.0, f"Specification invalide pour {spec.name} (tick_size/tick_value)"

        ticks_at_risk = signal.risk_distance / tick_size
        if ticks_at_risk <= 0:
            return 0.0, "Distance de stop nulle"

        loss_per_lot = ticks_at_risk * tick_value
        if loss_per_lot <= 0:
            return 0.0, "Perte par lot non calculable"

        raw_volume = risk_amount / loss_per_lot
        volume = round_to_step(raw_volume, spec.volume_step)
        volume = min(volume, spec.volume_max, self.cfg.max_lot)
        volume = round_to_step(volume, spec.volume_step)

        if volume < spec.volume_min:
            return 0.0, (
                f"Volume calcule ({raw_volume:.4f}) sous le minimum du broker "
                f"({spec.volume_min}). Stop trop large ou capital trop faible "
                f"pour {self.cfg.risk_per_trade_pct}% de risque."
            )
        return volume, ""

    def estimated_margin(self, spec: SymbolSpec, volume: float, price: float,
                         leverage: int) -> float:
        """Marge approchee requise. Approximation volontairement prudente."""
        lev = max(1, leverage)
        return volume * spec.contract_size * price / lev

    # ------------------------------------------------------------ verdict ----
    def evaluate(
        self,
        signal: Signal,
        spec: SymbolSpec,
        account: AccountSnapshot,
        positions: List[PositionInfo],
        now: datetime,
        spread_points: float,
    ) -> RiskDecision:
        decision = RiskDecision(approved=True)

        halt = self.check_circuit_breakers(account)
        if halt:
            return decision.reject(f"Moteur en arret : {halt}")

        ok, why = self.session_open(now)
        if not ok:
            return decision.reject(why)

        if self.trades_today >= self.cfg.max_trades_per_day > 0:
            return decision.reject(
                f"Quota de trades du jour atteint ({self.trades_today}/"
                f"{self.cfg.max_trades_per_day})"
            )

        if len(positions) >= self.cfg.max_open_positions > 0:
            return decision.reject(
                f"Trop de positions ouvertes ({len(positions)}/"
                f"{self.cfg.max_open_positions})"
            )

        same_symbol = [p for p in positions if p.symbol == signal.symbol]
        if len(same_symbol) >= self.cfg.max_positions_per_symbol > 0:
            return decision.reject(
                f"Position deja ouverte sur {signal.symbol} "
                f"({len(same_symbol)}/{self.cfg.max_positions_per_symbol})"
            )

        if spread_points > self.cfg.max_spread_points > 0:
            return decision.reject(
                f"Spread trop large sur {signal.symbol} : {spread_points:.0f} points "
                f"> {self.cfg.max_spread_points}"
            )

        # Le stop doit couvrir au moins le spread, sinon il est touche
        # instantanement a l'ouverture.
        spread_price = spread_points * spec.point
        if signal.risk_distance <= spread_price * 1.5:
            return decision.reject(
                "Stop trop proche par rapport au spread "
                f"({signal.risk_distance / spec.point:.0f} pts vs {spread_points:.0f} pts)"
            )

        volume, err = self.position_size(signal, spec, account)
        if volume <= 0:
            return decision.reject(err)

        price = signal.entry
        required = self.estimated_margin(spec, volume, price, account.leverage)
        remaining = account.margin_free - required
        floor = account.equity * self.cfg.min_free_margin_pct / 100.0
        if remaining < floor:
            return decision.reject(
                f"Marge libre insuffisante : il resterait {remaining:,.0f} "
                f"{account.currency} pour un plancher de {floor:,.0f}"
            )

        decision.volume = volume
        decision.reasons.append(
            f"Volume {volume} lot(s) pour {self.cfg.risk_per_trade_pct}% de risque "
            f"({account.equity * self.cfg.risk_per_trade_pct / 100.0:,.2f} "
            f"{account.currency})"
        )
        return decision

    def register_fill(self, symbol: str, bar_time: Optional[datetime]) -> None:
        self.trades_today += 1
        if bar_time is not None:
            self.last_entry_bar[symbol] = bar_time

    def in_cooldown(self, symbol: str, bar_time: Optional[datetime],
                    cooldown_bars: int, bar_minutes: int) -> bool:
        """Vrai si le symbole a deja traite il y a moins de `cooldown_bars`."""
        if cooldown_bars <= 0 or bar_time is None:
            return False
        last = self.last_entry_bar.get(symbol)
        if last is None:
            return False
        elapsed_minutes = (bar_time - last).total_seconds() / 60.0
        return elapsed_minutes < cooldown_bars * bar_minutes

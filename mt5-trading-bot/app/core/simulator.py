"""Simulateur de broker : meme surface que MT5Broker, sans terminal.

Il sert a trois choses :
  1. tester l'application de bout en bout sur une machine sans MetaTrader 5 ;
  2. faire tourner la strategie "a blanc" avant de la brancher sur un demo ;
  3. reproduire un bug sans risquer d'envoyer un ordre.

Les prix sont un mouvement brownien geometrique avec une volatilite par
symbole. Ce n'est pas un marche reel : ne jugez jamais une strategie sur ces
chiffres, utilisez le backtest sur donnees MT5 pour cela.
"""

from __future__ import annotations

import math
import threading
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from .broker import TIMEFRAMES, OrderResult
from .models import AccountSnapshot, PositionInfo, Side, SymbolSpec

_DEFAULTS = {
    "EURUSD": (1.0850, 5, 0.00012),
    "GBPUSD": (1.2700, 5, 0.00015),
    "USDJPY": (152.30, 3, 0.0150),
    "AUDUSD": (0.6600, 5, 0.00013),
    "USDCAD": (1.3600, 5, 0.00012),
    "XAUUSD": (2320.0, 2, 0.90),
}


class _SimPosition:
    def __init__(self, ticket, symbol, side, volume, price_open, sl, tp, magic, comment, opened):
        self.ticket = ticket
        self.symbol = symbol
        self.side = side
        self.volume = volume
        self.price_open = price_open
        self.sl = sl
        self.tp = tp
        self.magic = magic
        self.comment = comment
        self.time_open = opened


class SimulatedBroker:
    """Broker fictif, deterministe a graine fixe."""

    is_simulated = True

    def __init__(self, seed: int = 20240101, start_balance: float = 10_000.0):
        self._lock = threading.RLock()
        self._rng = np.random.default_rng(seed)
        self._connected = False
        self._balance = start_balance
        self._start_balance = start_balance
        self._next_ticket = 500_000
        self._positions: Dict[int, _SimPosition] = {}
        self._deals: List[dict] = []
        self._series: Dict[str, pd.Series] = {}
        self._cursor: Dict[str, int] = {}
        # Assez de M1 pour qu'une EMA200 en H4 soit definie (200 * 240 = 48 000).
        self._history_bars = 60_000
        self._resample_cache: Dict[tuple, pd.DataFrame] = {}

    # --------------------------------------------------------- connexion ----
    def connect(self, conn) -> Tuple[bool, str]:
        with self._lock:
            self._connected = True
            return True, (
                "Mode SIMULATION active - aucun ordre reel n'est envoye. "
                f"Capital fictif : {self._balance:,.2f} USD"
            )

    def shutdown(self) -> None:
        with self._lock:
            self._connected = False

    @property
    def connected(self) -> bool:
        return self._connected

    # ------------------------------------------------------- generation ----
    def _ensure_series(self, symbol: str) -> pd.Series:
        """Serie de prix en M1, generee une fois puis avancee tick par tick."""
        if symbol in self._series:
            return self._series[symbol]
        base, digits, vol = _DEFAULTS.get(symbol, (1.0, 5, 0.0001))
        n = self._history_bars
        # Marche alternant tendance et range, pour que les deux strategies
        # rencontrent leur regime.
        regime = np.sin(np.linspace(0, 6 * math.pi, n)) * vol * 0.22
        steps = self._rng.normal(0.0, vol, n) + regime
        prices = base + np.cumsum(steps)
        prices = np.maximum(prices, base * 0.5)
        end = datetime.now(timezone.utc).replace(second=0, microsecond=0)
        index = pd.date_range(end=end, periods=n, freq="1min")
        series = pd.Series(prices, index=index, name=symbol)
        self._series[symbol] = series
        self._cursor[symbol] = n - 1
        return series

    def advance(self, minutes: int = 1) -> None:
        """Fait avancer le temps simule (appele par le moteur a chaque cycle)."""
        with self._lock:
            for symbol, series in list(self._series.items()):
                _, _, vol = _DEFAULTS.get(symbol, (1.0, 5, 0.0001))
                last_time = series.index[-1]
                new_times, new_values = [], []
                price = float(series.iloc[-1])
                for i in range(max(1, minutes)):
                    price += float(self._rng.normal(0.0, vol))
                    new_times.append(last_time + timedelta(minutes=i + 1))
                    new_values.append(price)
                extra = pd.Series(new_values, index=pd.DatetimeIndex(new_times))
                combined = pd.concat([series, extra])
                self._series[symbol] = combined.iloc[-self._history_bars:]
            self._resample_cache.clear()
            self._check_exits()

    # ------------------------------------------------------------ compte ----
    def account(self) -> AccountSnapshot:
        with self._lock:
            floating = sum(self._position_profit(p) for p in self._positions.values())
            equity = self._balance + floating
            margin = sum(p.volume * 1000.0 for p in self._positions.values())
            return AccountSnapshot(
                login=99_000_001,
                server="Simulation",
                currency="USD",
                balance=self._balance,
                equity=equity,
                margin=margin,
                margin_free=max(0.0, equity - margin),
                margin_level=(equity / margin * 100.0) if margin else 0.0,
                profit=floating,
                leverage=100,
                is_demo=True,
                name="Compte simule",
            )

    def server_time(self) -> datetime:
        return datetime.now(timezone.utc)

    # ---------------------------------------------------------- symboles ----
    def ensure_symbol(self, symbol: str) -> bool:
        with self._lock:
            self._ensure_series(symbol)
            return True

    def symbol_spec(self, symbol: str) -> SymbolSpec:
        base, digits, vol = _DEFAULTS.get(symbol, (1.0, 5, 0.0001))
        point = 10.0 ** (-digits)
        # Valeur du tick approchee pour 1 lot standard, en USD.
        tick_value = 1.0 if digits == 5 else (0.68 if digits == 3 else 1.0)
        return SymbolSpec(
            name=symbol,
            digits=digits,
            point=point,
            volume_min=0.01,
            volume_max=50.0,
            volume_step=0.01,
            trade_tick_value=tick_value,
            trade_tick_size=point,
            stops_level=10,
            contract_size=100_000.0,
            filling_mode=3,
            spread=12,
        )

    def tick(self, symbol: str) -> Tuple[float, float, datetime]:
        with self._lock:
            series = self._ensure_series(symbol)
            spec = self.symbol_spec(symbol)
            mid = float(series.iloc[-1])
            half = spec.point * spec.spread / 2.0
            return (
                round(mid - half, spec.digits),
                round(mid + half, spec.digits),
                series.index[-1].to_pydatetime(),
            )

    def rates(self, symbol: str, timeframe: str, count: int) -> Optional[pd.DataFrame]:
        with self._lock:
            series = self._ensure_series(symbol)
            minutes = TIMEFRAMES.get(timeframe, 15)
            key = (symbol, minutes)
            df = self._resample_cache.get(key)
            if df is None:
                # Le reechantillonnage d'une longue serie coute cher : on le
                # garde en cache jusqu'au prochain advance().
                ohlc = series.resample(
                    f"{minutes}min", label="right", closed="right"
                ).ohlc().dropna()
                if ohlc.empty:
                    return None
                df = ohlc.copy()
                df.columns = ["open", "high", "low", "close"]
                df["tick_volume"] = 100.0
                df["spread"] = float(self.symbol_spec(symbol).spread)
                self._resample_cache[key] = df
            return df.tail(int(count)).copy()

    # --------------------------------------------------------- positions ----
    def _position_profit(self, p: _SimPosition) -> float:
        spec = self.symbol_spec(p.symbol)
        bid, ask, _ = self.tick(p.symbol)
        current = bid if p.side is Side.BUY else ask
        ticks = (current - p.price_open) * p.side.sign / spec.trade_tick_size
        return ticks * spec.trade_tick_value * p.volume

    def positions(self, magic: Optional[int] = None) -> List[PositionInfo]:
        with self._lock:
            out = []
            for p in self._positions.values():
                if magic is not None and p.magic != magic:
                    continue
                bid, ask, _ = self.tick(p.symbol)
                out.append(
                    PositionInfo(
                        ticket=p.ticket,
                        symbol=p.symbol,
                        side=p.side,
                        volume=p.volume,
                        price_open=p.price_open,
                        price_current=bid if p.side is Side.BUY else ask,
                        sl=p.sl,
                        tp=p.tp,
                        profit=self._position_profit(p),
                        swap=0.0,
                        magic=p.magic,
                        comment=p.comment,
                        time_open=p.time_open,
                    )
                )
            return out

    def send_market_order(
        self, symbol, side, volume, sl, tp, magic, deviation, comment=""
    ) -> OrderResult:
        with self._lock:
            spec = self.symbol_spec(symbol)
            bid, ask, now = self.tick(symbol)
            price = ask if side is Side.BUY else bid
            self._next_ticket += 1
            ticket = self._next_ticket
            self._positions[ticket] = _SimPosition(
                ticket, symbol, side, float(volume), price,
                float(sl or 0.0), float(tp or 0.0), magic, comment,
                datetime.now(timezone.utc),
            )
            return OrderResult(True, "Ordre simule execute", ticket, price)

    def modify_position(self, ticket: int, sl: float, tp: float) -> OrderResult:
        with self._lock:
            p = self._positions.get(ticket)
            if p is None:
                return OrderResult(False, f"Position {ticket} introuvable")
            p.sl, p.tp = float(sl or 0.0), float(tp or 0.0)
            return OrderResult(True, "SL/TP simules mis a jour", ticket)

    def close_position(self, ticket: int, deviation: int = 20) -> OrderResult:
        with self._lock:
            return self._close(ticket, "manuel")

    def _close(self, ticket: int, why: str) -> OrderResult:
        p = self._positions.pop(ticket, None)
        if p is None:
            return OrderResult(False, f"Position {ticket} introuvable")
        profit = self._position_profit(p)
        self._balance += profit
        bid, ask, _ = self.tick(p.symbol)
        price = bid if p.side is Side.BUY else ask
        self._deals.append(
            {
                "ticket": ticket,
                "position_id": ticket,
                "symbol": p.symbol,
                "volume": p.volume,
                "price": price,
                "profit": profit,
                "time": datetime.now(timezone.utc),
                "comment": why,
            }
        )
        return OrderResult(True, f"Position simulee fermee ({why})", ticket, price)

    def _check_exits(self) -> None:
        """Declenche SL/TP comme le ferait le serveur."""
        for ticket, p in list(self._positions.items()):
            bid, ask, _ = self.tick(p.symbol)
            price = bid if p.side is Side.BUY else ask
            if p.sl:
                hit = price <= p.sl if p.side is Side.BUY else price >= p.sl
                if hit:
                    self._close(ticket, "stop-loss")
                    continue
            if p.tp:
                hit = price >= p.tp if p.side is Side.BUY else price <= p.tp
                if hit:
                    self._close(ticket, "take-profit")

    # ---------------------------------------------------------- historique --
    def closed_pnl_since(self, since: datetime, magic: Optional[int] = None) -> float:
        with self._lock:
            return sum(d["profit"] for d in self._deals if d["time"] >= since)

    def closed_deals_since(self, since: datetime, magic: Optional[int] = None) -> List[dict]:
        with self._lock:
            return [d for d in self._deals if d["time"] >= since]

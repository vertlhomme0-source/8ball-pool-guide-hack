"""Structures de donnees partagees entre le moteur, le risque et l'interface."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import List, Optional


class Side(str, Enum):
    BUY = "BUY"
    SELL = "SELL"

    @property
    def sign(self) -> int:
        return 1 if self is Side.BUY else -1

    @property
    def opposite(self) -> "Side":
        return Side.SELL if self is Side.BUY else Side.BUY


@dataclass
class Signal:
    """Intention d'entree produite par une strategie, avant controle du risque."""

    symbol: str
    side: Side
    entry: float
    stop_loss: float
    take_profit: float
    confidence: float          # 0..1, sert au classement quand plusieurs signaux sortent
    reason: str                # explication lisible, affichee et journalisee
    atr: float = 0.0
    bar_time: Optional[datetime] = None

    @property
    def risk_distance(self) -> float:
        return abs(self.entry - self.stop_loss)

    @property
    def reward_distance(self) -> float:
        return abs(self.take_profit - self.entry)

    @property
    def rr(self) -> float:
        d = self.risk_distance
        return (self.reward_distance / d) if d > 0 else 0.0


@dataclass
class AccountSnapshot:
    login: int = 0
    server: str = ""
    currency: str = "USD"
    balance: float = 0.0
    equity: float = 0.0
    margin: float = 0.0
    margin_free: float = 0.0
    margin_level: float = 0.0
    profit: float = 0.0
    leverage: int = 0
    is_demo: bool = True
    name: str = ""


@dataclass
class PositionInfo:
    ticket: int
    symbol: str
    side: Side
    volume: float
    price_open: float
    price_current: float
    sl: float
    tp: float
    profit: float
    swap: float
    magic: int
    comment: str = ""
    time_open: Optional[datetime] = None


@dataclass
class SymbolSpec:
    """Specification d'un instrument, telle que fournie par le broker."""

    name: str
    digits: int
    point: float
    volume_min: float
    volume_max: float
    volume_step: float
    trade_tick_value: float
    trade_tick_size: float
    stops_level: int          # distance minimale SL/TP en points imposee par le broker
    contract_size: float = 100000.0
    filling_mode: int = 0
    spread: int = 0


@dataclass
class RiskDecision:
    """Verdict du gestionnaire de risque sur un signal."""

    approved: bool
    volume: float = 0.0
    reasons: List[str] = field(default_factory=list)

    def reject(self, reason: str) -> "RiskDecision":
        self.approved = False
        self.reasons.append(reason)
        return self


@dataclass
class EngineStats:
    """Etat agrege du moteur, pousse vers l'interface a chaque cycle."""

    running: bool = False
    connected: bool = False
    live_orders: bool = False
    account: AccountSnapshot = field(default_factory=AccountSnapshot)
    open_positions: int = 0
    trades_today: int = 0
    pnl_today: float = 0.0
    day_start_equity: float = 0.0
    peak_equity: float = 0.0
    drawdown_pct: float = 0.0
    halted: bool = False
    halt_reason: str = ""
    last_cycle: Optional[datetime] = None
    last_error: str = ""

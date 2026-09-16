"""Acces au broker : implementation MetaTrader 5 + simulateur hors-ligne.

Les deux classes exposent exactement la meme surface, ce qui permet de faire
tourner le moteur, l'interface et le backtest sans terminal MT5 installe
(utile pour verifier l'application avant de la brancher sur un vrai compte).

Regle importante : le paquet `MetaTrader5` n'est pas thread-safe. Toutes les
methodes de `MT5Broker` doivent etre appelees depuis un seul et meme thread
(celui du moteur). Un verrou reentrant protege malgre tout les appels.
"""

from __future__ import annotations

import math
import threading
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from .models import AccountSnapshot, PositionInfo, Side, SymbolSpec

# Unites de temps supportees -> duree en minutes
TIMEFRAMES: Dict[str, int] = {
    "M1": 1, "M5": 5, "M15": 15, "M30": 30,
    "H1": 60, "H4": 240, "D1": 1440,
}


class BrokerError(RuntimeError):
    pass


class OrderResult:
    def __init__(self, ok: bool, message: str, ticket: int = 0, price: float = 0.0):
        self.ok = ok
        self.message = message
        self.ticket = ticket
        self.price = price

    def __bool__(self) -> bool:
        return self.ok


# ============================================================ MetaTrader 5 ====
class MT5Broker:
    """Adaptateur du paquet officiel `MetaTrader5` (Windows uniquement)."""

    is_simulated = False

    def __init__(self) -> None:
        self._mt5 = None
        self._lock = threading.RLock()
        self._connected = False
        self._spec_cache: Dict[str, SymbolSpec] = {}

    # ------------------------------------------------------------ import ----
    def _api(self):
        if self._mt5 is None:
            try:
                import MetaTrader5 as mt5  # noqa: N813
            except ImportError as exc:  # pragma: no cover - depend de la plateforme
                raise BrokerError(
                    "Le paquet MetaTrader5 n'est pas installe ou n'est pas disponible "
                    "sur ce systeme (il requiert Windows). Installez-le avec "
                    "`pip install MetaTrader5`, ou activez le mode simulation."
                ) from exc
            self._mt5 = mt5
        return self._mt5

    # --------------------------------------------------------- connexion ----
    def connect(self, conn) -> Tuple[bool, str]:
        with self._lock:
            mt5 = self._api()
            kwargs = {}
            if conn.terminal_path:
                kwargs["path"] = conn.terminal_path
            if not mt5.initialize(**kwargs):
                code, msg = mt5.last_error()
                return False, f"initialize() a echoue ({code}) : {msg}"

            if conn.login:
                ok = mt5.login(
                    int(conn.login), password=conn.password, server=conn.server
                )
                if not ok:
                    code, msg = mt5.last_error()
                    mt5.shutdown()
                    return False, f"login() a echoue ({code}) : {msg}"

            info = mt5.account_info()
            if info is None:
                mt5.shutdown()
                return False, "Aucun compte actif dans le terminal MetaTrader 5."

            self._connected = True
            self._spec_cache.clear()
            kind = "DEMO" if info.trade_mode == mt5.ACCOUNT_TRADE_MODE_DEMO else "REEL"
            return True, f"Connecte au compte {info.login} ({kind}) sur {info.server}"

    def shutdown(self) -> None:
        with self._lock:
            if self._mt5 is not None and self._connected:
                try:
                    self._mt5.shutdown()
                except Exception:  # pragma: no cover - fermeture best-effort
                    pass
            self._connected = False

    @property
    def connected(self) -> bool:
        return self._connected

    # ------------------------------------------------------------ compte ----
    def account(self) -> Optional[AccountSnapshot]:
        with self._lock:
            mt5 = self._api()
            info = mt5.account_info()
            if info is None:
                return None
            return AccountSnapshot(
                login=info.login,
                server=info.server,
                currency=info.currency,
                balance=info.balance,
                equity=info.equity,
                margin=info.margin,
                margin_free=info.margin_free,
                margin_level=info.margin_level,
                profit=info.profit,
                leverage=info.leverage,
                is_demo=info.trade_mode != mt5.ACCOUNT_TRADE_MODE_REAL,
                name=info.name,
            )

    def server_time(self) -> datetime:
        """Heure du serveur, approchee par l'horodatage du dernier tick connu."""
        with self._lock:
            mt5 = self._api()
            for sym in (mt5.symbols_get() or [])[:1]:
                tick = mt5.symbol_info_tick(sym.name)
                if tick is not None and tick.time:
                    return datetime.fromtimestamp(tick.time, tz=timezone.utc)
        return datetime.now(timezone.utc)

    # ---------------------------------------------------------- symboles ----
    def ensure_symbol(self, symbol: str) -> bool:
        with self._lock:
            mt5 = self._api()
            info = mt5.symbol_info(symbol)
            if info is None:
                return False
            if not info.visible:
                return bool(mt5.symbol_select(symbol, True))
            return True

    def symbol_spec(self, symbol: str) -> Optional[SymbolSpec]:
        with self._lock:
            mt5 = self._api()
            info = mt5.symbol_info(symbol)
            if info is None:
                return None
            spec = SymbolSpec(
                name=info.name,
                digits=info.digits,
                point=info.point,
                volume_min=info.volume_min,
                volume_max=info.volume_max,
                volume_step=info.volume_step,
                trade_tick_value=info.trade_tick_value,
                trade_tick_size=info.trade_tick_size or info.point,
                stops_level=info.trade_stops_level,
                contract_size=info.trade_contract_size,
                filling_mode=info.filling_mode,
                spread=info.spread,
            )
            self._spec_cache[symbol] = spec
            return spec

    def tick(self, symbol: str) -> Optional[Tuple[float, float, datetime]]:
        with self._lock:
            mt5 = self._api()
            t = mt5.symbol_info_tick(symbol)
            if t is None or (t.bid == 0 and t.ask == 0):
                return None
            return t.bid, t.ask, datetime.fromtimestamp(t.time, tz=timezone.utc)

    def rates(self, symbol: str, timeframe: str, count: int) -> Optional[pd.DataFrame]:
        with self._lock:
            mt5 = self._api()
            tf = getattr(mt5, f"TIMEFRAME_{timeframe}", None)
            if tf is None:
                raise BrokerError(f"Unite de temps inconnue : {timeframe}")
            data = mt5.copy_rates_from_pos(symbol, tf, 0, int(count))
            if data is None or len(data) == 0:
                return None
            return _rates_to_frame(data)

    # --------------------------------------------------------- positions ----
    def positions(self, magic: Optional[int] = None) -> List[PositionInfo]:
        with self._lock:
            mt5 = self._api()
            raw = mt5.positions_get()
            if raw is None:
                return []
            out: List[PositionInfo] = []
            for p in raw:
                if magic is not None and p.magic != magic:
                    continue
                out.append(
                    PositionInfo(
                        ticket=p.ticket,
                        symbol=p.symbol,
                        side=Side.BUY if p.type == mt5.POSITION_TYPE_BUY else Side.SELL,
                        volume=p.volume,
                        price_open=p.price_open,
                        price_current=p.price_current,
                        sl=p.sl,
                        tp=p.tp,
                        profit=p.profit,
                        swap=p.swap,
                        magic=p.magic,
                        comment=p.comment,
                        time_open=datetime.fromtimestamp(p.time, tz=timezone.utc),
                    )
                )
            return out

    def _filling_modes(self, symbol: str) -> List[int]:
        """Modes d'execution a tenter, du plus probable au plus rare."""
        mt5 = self._api()
        spec = self._spec_cache.get(symbol) or self.symbol_spec(symbol)
        modes: List[int] = []
        mask = spec.filling_mode if spec else 0
        # SYMBOL_FILLING_FOK = 1, SYMBOL_FILLING_IOC = 2 (masque de bits)
        if mask & 2:
            modes.append(mt5.ORDER_FILLING_IOC)
        if mask & 1:
            modes.append(mt5.ORDER_FILLING_FOK)
        modes.append(mt5.ORDER_FILLING_RETURN)
        return modes

    def send_market_order(
        self,
        symbol: str,
        side: Side,
        volume: float,
        sl: float,
        tp: float,
        magic: int,
        deviation: int,
        comment: str = "",
    ) -> OrderResult:
        with self._lock:
            mt5 = self._api()
            tick = self.tick(symbol)
            if tick is None:
                return OrderResult(False, f"Pas de cotation pour {symbol}")
            bid, ask, _ = tick
            price = ask if side is Side.BUY else bid
            order_type = mt5.ORDER_TYPE_BUY if side is Side.BUY else mt5.ORDER_TYPE_SELL

            last_msg = "Echec inconnu"
            for filling in self._filling_modes(symbol):
                request = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "symbol": symbol,
                    "volume": float(volume),
                    "type": order_type,
                    "price": float(price),
                    "sl": float(sl) if sl else 0.0,
                    "tp": float(tp) if tp else 0.0,
                    "deviation": int(deviation),
                    "magic": int(magic),
                    "comment": comment[:31],
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": filling,
                }
                result = mt5.order_send(request)
                if result is None:
                    code, msg = mt5.last_error()
                    last_msg = f"order_send() a renvoye None ({code}: {msg})"
                    continue
                if result.retcode == mt5.TRADE_RETCODE_DONE:
                    return OrderResult(True, "Ordre execute", result.order, result.price)
                last_msg = f"retcode {result.retcode} : {result.comment}"
                # 10030 = mode de remplissage refuse : on tente le suivant
                if result.retcode != 10030:
                    break
            return OrderResult(False, last_msg)

    def modify_position(self, ticket: int, sl: float, tp: float) -> OrderResult:
        with self._lock:
            mt5 = self._api()
            positions = mt5.positions_get(ticket=ticket)
            if not positions:
                return OrderResult(False, f"Position {ticket} introuvable")
            pos = positions[0]
            request = {
                "action": mt5.TRADE_ACTION_SLTP,
                "position": int(ticket),
                "symbol": pos.symbol,
                "sl": float(sl) if sl else 0.0,
                "tp": float(tp) if tp else 0.0,
            }
            result = mt5.order_send(request)
            if result is None:
                code, msg = mt5.last_error()
                return OrderResult(False, f"order_send() None ({code}: {msg})")
            if result.retcode == mt5.TRADE_RETCODE_DONE:
                return OrderResult(True, "SL/TP mis a jour", ticket)
            return OrderResult(False, f"retcode {result.retcode} : {result.comment}")

    def close_position(self, ticket: int, deviation: int = 20) -> OrderResult:
        with self._lock:
            mt5 = self._api()
            positions = mt5.positions_get(ticket=ticket)
            if not positions:
                return OrderResult(False, f"Position {ticket} introuvable")
            pos = positions[0]
            tick = self.tick(pos.symbol)
            if tick is None:
                return OrderResult(False, f"Pas de cotation pour {pos.symbol}")
            bid, ask, _ = tick
            is_buy = pos.type == mt5.POSITION_TYPE_BUY
            price = bid if is_buy else ask
            order_type = mt5.ORDER_TYPE_SELL if is_buy else mt5.ORDER_TYPE_BUY

            last_msg = "Echec inconnu"
            for filling in self._filling_modes(pos.symbol):
                request = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "symbol": pos.symbol,
                    "volume": float(pos.volume),
                    "type": order_type,
                    "position": int(ticket),
                    "price": float(price),
                    "deviation": int(deviation),
                    "magic": int(pos.magic),
                    "comment": "close",
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": filling,
                }
                result = mt5.order_send(request)
                if result is None:
                    code, msg = mt5.last_error()
                    last_msg = f"order_send() None ({code}: {msg})"
                    continue
                if result.retcode == mt5.TRADE_RETCODE_DONE:
                    return OrderResult(True, "Position fermee", ticket, result.price)
                last_msg = f"retcode {result.retcode} : {result.comment}"
                if result.retcode != 10030:
                    break
            return OrderResult(False, last_msg)

    def closed_pnl_since(self, since: datetime, magic: Optional[int] = None) -> float:
        """P&L realise (profit + commission + swap) depuis `since`."""
        with self._lock:
            mt5 = self._api()
            deals = mt5.history_deals_get(since, datetime.now(timezone.utc) + timedelta(days=1))
            if not deals:
                return 0.0
            total = 0.0
            for d in deals:
                if magic is not None and d.magic != magic:
                    continue
                if d.entry == mt5.DEAL_ENTRY_IN:
                    continue  # une entree ne realise rien
                total += d.profit + d.commission + d.swap
            return total

    def closed_deals_since(self, since: datetime, magic: Optional[int] = None) -> List[dict]:
        with self._lock:
            mt5 = self._api()
            deals = mt5.history_deals_get(since, datetime.now(timezone.utc) + timedelta(days=1))
            out: List[dict] = []
            for d in deals or []:
                if magic is not None and d.magic != magic:
                    continue
                if d.entry == mt5.DEAL_ENTRY_IN:
                    continue
                out.append(
                    {
                        "ticket": d.ticket,
                        "position_id": d.position_id,
                        "symbol": d.symbol,
                        "volume": d.volume,
                        "price": d.price,
                        "profit": d.profit + d.commission + d.swap,
                        "time": datetime.fromtimestamp(d.time, tz=timezone.utc),
                        "comment": d.comment,
                    }
                )
            return out


def _rates_to_frame(data) -> pd.DataFrame:
    df = pd.DataFrame(data)
    df["time"] = pd.to_datetime(df["time"], unit="s", utc=True)
    df = df.set_index("time")
    keep = [c for c in ("open", "high", "low", "close", "tick_volume", "spread") if c in df]
    return df[keep].astype(float)

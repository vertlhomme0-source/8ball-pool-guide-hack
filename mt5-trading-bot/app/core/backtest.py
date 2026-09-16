"""Backtest sur donnees historiques.

Hypotheses assumees, a garder en tete en lisant les resultats :

* une seule position a la fois par symbole ;
* execution a la cloture de la bougie de signal, plus le spread ;
* si le stop et l'objectif sont touches dans la meme bougie, on compte le
  **stop** (hypothese pessimiste : on ne connait pas l'ordre intra-bougie) ;
* pas de swap, pas de commission, pas de slippage variable, pas de gap de
  week-end.

Un backtest flatteur ne prouve rien. Il sert surtout a eliminer les reglages
manifestement mauvais.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Callable, Dict, List, Optional

import numpy as np
import pandas as pd

from ..config import RiskConfig, StrategyConfig
from . import indicators as ind
from .models import Side, Signal, SymbolSpec
from .risk import round_to_step
from .strategies import build_strategy


@dataclass
class BacktestTrade:
    symbol: str
    side: str
    entry_time: datetime
    entry: float
    exit_time: Optional[datetime]
    exit: float
    volume: float
    profit: float
    r_multiple: float
    outcome: str          # "TP" | "SL" | "fin de periode"
    reason: str


@dataclass
class BacktestResult:
    trades: List[BacktestTrade] = field(default_factory=list)
    equity: List[float] = field(default_factory=list)
    times: List[datetime] = field(default_factory=list)
    start_balance: float = 10_000.0
    bars_tested: int = 0
    note: str = ""

    # ------------------------------------------------------ statistiques ----
    @property
    def final_balance(self) -> float:
        return self.equity[-1] if self.equity else self.start_balance

    def summary(self) -> Dict[str, float]:
        profits = [t.profit for t in self.trades]
        if not profits:
            return {
                "trades": 0, "win_rate": 0.0, "profit_factor": 0.0, "net": 0.0,
                "max_drawdown_pct": 0.0, "expectancy": 0.0, "avg_r": 0.0,
                "return_pct": 0.0, "wins": 0, "losses": 0,
                "best": 0.0, "worst": 0.0, "max_consec_losses": 0,
            }
        wins = [p for p in profits if p > 0]
        losses = [p for p in profits if p <= 0]
        gross_profit = sum(wins)
        gross_loss = abs(sum(losses))

        curve = np.array(self.equity, dtype=float)
        peaks = np.maximum.accumulate(curve)
        drawdowns = np.where(peaks > 0, (peaks - curve) / peaks * 100.0, 0.0)

        streak = worst_streak = 0
        for p in profits:
            streak = streak + 1 if p <= 0 else 0
            worst_streak = max(worst_streak, streak)

        return {
            "trades": len(profits),
            "wins": len(wins),
            "losses": len(losses),
            "win_rate": len(wins) / len(profits) * 100.0,
            "profit_factor": (gross_profit / gross_loss) if gross_loss > 0 else float("inf"),
            "net": gross_profit - gross_loss,
            "return_pct": (self.final_balance / self.start_balance - 1.0) * 100.0,
            "max_drawdown_pct": float(drawdowns.max()) if len(drawdowns) else 0.0,
            "expectancy": float(np.mean(profits)),
            "avg_r": float(np.mean([t.r_multiple for t in self.trades])),
            "best": max(profits),
            "worst": min(profits),
            "max_consec_losses": worst_streak,
        }


def run_backtest(
    bars: Dict[str, pd.DataFrame],
    htf_bars: Dict[str, pd.DataFrame],
    specs: Dict[str, SymbolSpec],
    strategy_cfg: StrategyConfig,
    risk_cfg: RiskConfig,
    start_balance: float = 10_000.0,
    progress: Optional[Callable[[int, int], bool]] = None,
) -> BacktestResult:
    """Rejoue la strategie bougie par bougie.

    `progress(courant, total)` peut renvoyer False pour interrompre proprement.
    """
    strategy = build_strategy(strategy_cfg)
    result = BacktestResult(start_balance=start_balance)
    balance = start_balance

    enriched: Dict[str, pd.DataFrame] = {}
    htf_enriched: Dict[str, pd.DataFrame] = {}
    for symbol, df in bars.items():
        if df is None or len(df) < ind.required_bars(strategy_cfg) + 10:
            continue
        enriched[symbol] = ind.enrich(df, strategy_cfg)
        htf = htf_bars.get(symbol)
        if htf is not None and len(htf) > ind.required_bars(strategy_cfg):
            htf_enriched[symbol] = ind.enrich(htf, strategy_cfg)

    if not enriched:
        result.note = "Historique insuffisant pour lancer le backtest."
        return result

    # Axe de temps commun, ordonne.
    timeline = sorted(set().union(*[set(df.index) for df in enriched.values()]))
    warmup = ind.required_bars(strategy_cfg)
    open_trades: Dict[str, dict] = {}
    result.bars_tested = max(0, len(timeline) - warmup)

    for step, stamp in enumerate(timeline):
        if step < warmup:
            continue
        if progress is not None and step % 250 == 0:
            if progress(step - warmup, result.bars_tested) is False:
                result.note = "Backtest interrompu."
                break

        for symbol, df in enriched.items():
            if stamp not in df.index:
                continue
            row = df.loc[stamp]
            spec = specs.get(symbol)
            if spec is None:
                continue
            spread = spec.spread * spec.point

            # --- 1. Sortie d'une position ouverte sur cette bougie ---------
            trade = open_trades.get(symbol)
            if trade is not None:
                side = trade["side"]
                hit_sl = row["low"] <= trade["sl"] if side is Side.BUY else row["high"] >= trade["sl"]
                hit_tp = row["high"] >= trade["tp"] if side is Side.BUY else row["low"] <= trade["tp"]
                exit_price = outcome = None
                if hit_sl:                      # pessimiste : le stop d'abord
                    exit_price, outcome = trade["sl"], "SL"
                elif hit_tp:
                    exit_price, outcome = trade["tp"], "TP"
                if exit_price is not None:
                    profit = _pnl(trade, exit_price, spec)
                    balance += profit
                    risk_amount = trade["risk_amount"]
                    result.trades.append(
                        BacktestTrade(
                            symbol=symbol, side=side.value,
                            entry_time=trade["time"], entry=trade["entry"],
                            exit_time=stamp, exit=exit_price, volume=trade["volume"],
                            profit=profit,
                            r_multiple=profit / risk_amount if risk_amount else 0.0,
                            outcome=outcome, reason=trade["reason"],
                        )
                    )
                    result.equity.append(balance)
                    result.times.append(stamp)
                    open_trades.pop(symbol, None)
                    continue  # pas de reentree immediate sur la meme bougie

            # --- 2. Recherche d'entree ------------------------------------
            if symbol in open_trades:
                continue
            if len(open_trades) >= risk_cfg.max_open_positions > 0:
                continue
            window = df.loc[:stamp]
            if len(window) < warmup:
                continue
            htf_window = None
            htf_df = htf_enriched.get(symbol)
            if htf_df is not None:
                sub = htf_df.loc[:stamp]
                htf_window = sub if len(sub) > 2 else None

            signal = strategy.generate(symbol, window, htf_window)
            if signal is None:
                continue

            entry = signal.entry + (spread if signal.side is Side.BUY else -spread)
            sl_dist, tp_dist = signal.risk_distance, signal.reward_distance
            min_dist = max(spec.stops_level, 0) * spec.point * 1.2
            if sl_dist < min_dist:
                ratio = tp_dist / sl_dist if sl_dist else 1.0
                sl_dist = min_dist
                tp_dist = sl_dist * ratio
            sl = entry - signal.side.sign * sl_dist
            tp = entry + signal.side.sign * tp_dist

            risk_amount = balance * risk_cfg.risk_per_trade_pct / 100.0
            tick_size = spec.trade_tick_size or spec.point
            loss_per_lot = (sl_dist / tick_size) * spec.trade_tick_value
            if loss_per_lot <= 0:
                continue
            volume = round_to_step(risk_amount / loss_per_lot, spec.volume_step)
            volume = min(volume, spec.volume_max, risk_cfg.max_lot)
            volume = round_to_step(volume, spec.volume_step)
            if volume < spec.volume_min:
                continue

            open_trades[symbol] = {
                "side": signal.side, "entry": entry, "sl": sl, "tp": tp,
                "volume": volume, "time": stamp, "reason": signal.reason,
                "risk_amount": (sl_dist / tick_size) * spec.trade_tick_value * volume,
            }

    # Positions encore ouvertes en fin de periode : valorisees au dernier prix.
    for symbol, trade in open_trades.items():
        df = enriched[symbol]
        spec = specs[symbol]
        last_price = float(df["close"].iloc[-1])
        profit = _pnl(trade, last_price, spec)
        balance += profit
        result.trades.append(
            BacktestTrade(
                symbol=symbol, side=trade["side"].value, entry_time=trade["time"],
                entry=trade["entry"], exit_time=df.index[-1], exit=last_price,
                volume=trade["volume"], profit=profit,
                r_multiple=profit / trade["risk_amount"] if trade["risk_amount"] else 0.0,
                outcome="fin de periode", reason=trade["reason"],
            )
        )
        result.equity.append(balance)
        result.times.append(df.index[-1])

    if not result.equity:
        result.equity = [start_balance]
        result.times = [timeline[-1]] if timeline else []
        if not result.note:
            result.note = "Aucun trade genere sur la periode (filtres trop stricts ?)."
    return result


def _pnl(trade: dict, exit_price: float, spec: SymbolSpec) -> float:
    tick_size = spec.trade_tick_size or spec.point
    ticks = (exit_price - trade["entry"]) * trade["side"].sign / tick_size
    return ticks * spec.trade_tick_value * trade["volume"]

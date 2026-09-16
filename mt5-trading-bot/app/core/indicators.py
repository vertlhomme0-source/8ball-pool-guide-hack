"""Indicateurs techniques, en pandas/numpy uniquement (pas de TA-Lib a compiler).

Toutes les fonctions retournent une Series alignee sur l'index d'entree et
n'introduisent aucun biais de look-ahead : la valeur a l'index i n'utilise que
les bougies <= i.
"""

from __future__ import annotations

import numpy as np
import pandas as pd


def ema(series: pd.Series, period: int) -> pd.Series:
    return series.ewm(span=period, adjust=False, min_periods=period).mean()


def sma(series: pd.Series, period: int) -> pd.Series:
    return series.rolling(period, min_periods=period).mean()


def rma(series: pd.Series, period: int) -> pd.Series:
    """Moyenne lissee de Wilder, utilisee par RSI / ATR / ADX."""
    return series.ewm(alpha=1.0 / period, adjust=False, min_periods=period).mean()


def rsi(close: pd.Series, period: int = 14) -> pd.Series:
    delta = close.diff()
    gain = delta.clip(lower=0.0)
    loss = -delta.clip(upper=0.0)
    avg_gain = rma(gain, period)
    avg_loss = rma(loss, period)
    rs = avg_gain / avg_loss.replace(0.0, np.nan)
    out = 100.0 - (100.0 / (1.0 + rs))
    # avg_loss == 0 => RSI 100 (que des hausses) ; avg_gain == 0 => RSI 0
    out = out.where(avg_loss != 0.0, 100.0)
    out = out.where(avg_gain != 0.0, 0.0)
    return out


def true_range(high: pd.Series, low: pd.Series, close: pd.Series) -> pd.Series:
    prev_close = close.shift(1)
    ranges = pd.concat(
        [high - low, (high - prev_close).abs(), (low - prev_close).abs()], axis=1
    )
    return ranges.max(axis=1)


def atr(high: pd.Series, low: pd.Series, close: pd.Series, period: int = 14) -> pd.Series:
    return rma(true_range(high, low, close), period)


def adx(
    high: pd.Series, low: pd.Series, close: pd.Series, period: int = 14
) -> tuple[pd.Series, pd.Series, pd.Series]:
    """Retourne (ADX, +DI, -DI)."""
    up_move = high.diff()
    down_move = -low.diff()
    plus_dm = pd.Series(
        np.where((up_move > down_move) & (up_move > 0), up_move, 0.0), index=high.index
    )
    minus_dm = pd.Series(
        np.where((down_move > up_move) & (down_move > 0), down_move, 0.0), index=high.index
    )
    tr = rma(true_range(high, low, close), period)
    tr_safe = tr.replace(0.0, np.nan)
    plus_di = 100.0 * rma(plus_dm, period) / tr_safe
    minus_di = 100.0 * rma(minus_dm, period) / tr_safe
    denom = (plus_di + minus_di).replace(0.0, np.nan)
    dx = 100.0 * (plus_di - minus_di).abs() / denom
    return rma(dx, period), plus_di, minus_di


def bollinger(
    close: pd.Series, period: int = 20, std_mult: float = 2.0
) -> tuple[pd.Series, pd.Series, pd.Series]:
    """Retourne (bande basse, moyenne, bande haute)."""
    mid = sma(close, period)
    # ddof=0 : ecart-type de population, convention des plateformes de trading
    dev = close.rolling(period, min_periods=period).std(ddof=0) * std_mult
    return mid - dev, mid, mid + dev


def swing_high(high: pd.Series, lookback: int = 10) -> pd.Series:
    return high.rolling(lookback, min_periods=1).max()


def swing_low(low: pd.Series, lookback: int = 10) -> pd.Series:
    return low.rolling(lookback, min_periods=1).min()


def enrich(df: pd.DataFrame, cfg) -> pd.DataFrame:
    """Ajoute toutes les colonnes d'indicateurs attendues par les strategies.

    `df` doit contenir open/high/low/close. La copie evite de muter le cache
    de bougies partage avec le reste du moteur.
    """
    out = df.copy()
    close, high, low = out["close"], out["high"], out["low"]

    out["ema_fast"] = ema(close, cfg.ema_fast)
    out["ema_slow"] = ema(close, cfg.ema_slow)
    out["ema_trend"] = ema(close, cfg.ema_trend)
    out["rsi"] = rsi(close, cfg.rsi_period)
    out["atr"] = atr(high, low, close, cfg.atr_period)
    out["adx"], out["plus_di"], out["minus_di"] = adx(high, low, close, cfg.adx_period)
    out["bb_low"], out["bb_mid"], out["bb_high"] = bollinger(close, cfg.bb_period, cfg.bb_std)
    out["swing_high"] = swing_high(high, 10)
    out["swing_low"] = swing_low(low, 10)
    return out


def required_bars(cfg) -> int:
    """Nombre minimal de bougies pour que tous les indicateurs soient definis."""
    return max(cfg.ema_trend, cfg.adx_period * 3, cfg.bb_period, cfg.rsi_period * 3) + 20

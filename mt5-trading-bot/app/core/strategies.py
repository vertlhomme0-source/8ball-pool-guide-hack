"""Strategies d'entree.

Regles communes a toutes les strategies :

* elles ne voient que des bougies **cloturees** (le moteur retire la bougie en
  formation avant l'appel), donc aucun signal ne peut se "repeindre" ;
* elles renvoient toujours un stop-loss et un take-profit, jamais une entree
  nue ;
* le prix d'entree renvoye est la cloture de reference ; le moteur reancre
  ensuite SL/TP sur le prix reellement traite en conservant les distances.

Aucune de ces strategies n'est une garantie de gain. Elles filtrent
beaucoup pour privilegier la qualite des entrees, ce qui donne peu de trades.
"""

from __future__ import annotations

from typing import Optional

import pandas as pd

from ..config import StrategyConfig
from .models import Side, Signal


class Strategy:
    """Interface commune."""

    name = "base"
    label = "Base"
    description = ""

    def __init__(self, cfg: StrategyConfig):
        self.cfg = cfg

    def generate(
        self, symbol: str, ltf: pd.DataFrame, htf: Optional[pd.DataFrame]
    ) -> Optional[Signal]:
        raise NotImplementedError

    # ------------------------------------------------------------ outils ----
    def _htf_bias(self, htf: Optional[pd.DataFrame]) -> Optional[Side]:
        """Sens autorise par l'unite de temps superieure, None si indecis."""
        if htf is None or len(htf) < 2:
            return None
        row = htf.iloc[-1]
        if _isnan(row.get("ema_fast"), row.get("ema_slow"), row.get("close")):
            return None
        if row["close"] > row["ema_slow"] and row["ema_fast"] > row["ema_slow"]:
            return Side.BUY
        if row["close"] < row["ema_slow"] and row["ema_fast"] < row["ema_slow"]:
            return Side.SELL
        return None

    def _build(
        self,
        symbol: str,
        side: Side,
        entry: float,
        atr_value: float,
        confidence: float,
        reason: str,
        bar_time,
        sl_mult: Optional[float] = None,
        tp_mult: Optional[float] = None,
    ) -> Optional[Signal]:
        sl_mult = self.cfg.sl_atr_mult if sl_mult is None else sl_mult
        tp_mult = self.cfg.tp_atr_mult if tp_mult is None else tp_mult
        if atr_value <= 0:
            return None
        sl_dist = atr_value * sl_mult
        tp_dist = atr_value * tp_mult
        if sl_dist <= 0 or tp_dist <= 0:
            return None
        sl = entry - side.sign * sl_dist
        tp = entry + side.sign * tp_dist
        signal = Signal(
            symbol=symbol,
            side=side,
            entry=float(entry),
            stop_loss=float(sl),
            take_profit=float(tp),
            confidence=max(0.0, min(1.0, confidence)),
            reason=reason,
            atr=float(atr_value),
            bar_time=bar_time,
        )
        if signal.rr < self.cfg.min_rr:
            return None
        return signal


def _isnan(*values) -> bool:
    for v in values:
        if v is None or pd.isna(v):
            return True
    return False


class TrendPullbackStrategy(Strategy):
    """Suivi de tendance sur repli.

    On attend un marche directionnel (ADX eleve), une tendance claire
    (empilement des EMA), puis un repli qui vient toucher l'EMA rapide et
    repartir dans le sens de la tendance. On n'achete pas la cassure, on
    achete le repli : le stop est plus proche, donc le lot est plus gros a
    risque egal.
    """

    name = "trend_pullback"
    label = "Suivi de tendance (repli)"
    description = "ADX fort + empilement EMA + repli sur EMA rapide avec rejet."

    def generate(self, symbol, ltf, htf) -> Optional[Signal]:
        cfg = self.cfg
        if len(ltf) < 3:
            return None
        cur, prev = ltf.iloc[-1], ltf.iloc[-2]
        if _isnan(
            cur.get("ema_fast"), cur.get("ema_slow"), cur.get("ema_trend"),
            cur.get("atr"), cur.get("adx"), cur.get("rsi"),
        ):
            return None
        if cur["adx"] < cfg.adx_trend_min:
            return None
        if cfg.min_atr_points > 0 and cur["atr"] < cfg.min_atr_points:
            return None

        htf_bias = self._htf_bias(htf)
        if cfg.require_htf_alignment and htf_bias is None:
            return None

        up = (
            cur["ema_fast"] > cur["ema_slow"] > cur["ema_trend"]
            and cur["close"] > cur["ema_fast"]
        )
        down = (
            cur["ema_fast"] < cur["ema_slow"] < cur["ema_trend"]
            and cur["close"] < cur["ema_fast"]
        )
        if not (up or down):
            return None
        side = Side.BUY if up else Side.SELL
        if cfg.require_htf_alignment and htf_bias is not side:
            return None

        # Le repli : une des deux dernieres bougies a touche l'EMA rapide.
        if side is Side.BUY:
            touched = (prev["low"] <= prev["ema_fast"]) or (cur["low"] <= cur["ema_fast"])
            rejected = cur["close"] > cur["open"] and cur["close"] > prev["high"] * 0.9999
            rsi_ok = 40.0 <= cur["rsi"] <= 68.0
            di_ok = cur.get("plus_di", 0) > cur.get("minus_di", 0)
        else:
            touched = (prev["high"] >= prev["ema_fast"]) or (cur["high"] >= cur["ema_fast"])
            rejected = cur["close"] < cur["open"] and cur["close"] < prev["low"] * 1.0001
            rsi_ok = 32.0 <= cur["rsi"] <= 60.0
            di_ok = cur.get("minus_di", 0) > cur.get("plus_di", 0)
        if not (touched and rejected and rsi_ok and di_ok):
            return None

        # Confiance : part des confirmations optionnelles reunies.
        score = 0.45
        score += 0.15 if cur["adx"] >= cfg.adx_trend_min + 8 else 0.0
        score += 0.15 if htf_bias is side else 0.0
        spread_ema = abs(cur["ema_fast"] - cur["ema_slow"])
        score += 0.15 if spread_ema > cur["atr"] * 0.3 else 0.0
        score += 0.10 if abs(cur["close"] - cur["open"]) > cur["atr"] * 0.4 else 0.0

        sens = "haussiere" if side is Side.BUY else "baissiere"
        reason = (
            f"Tendance {sens} (ADX {cur['adx']:.0f}), repli sur EMA{cfg.ema_fast} "
            f"puis rejet, RSI {cur['rsi']:.0f}"
        )
        return self._build(symbol, side, cur["close"], cur["atr"], score, reason, ltf.index[-1])


class MeanReversionStrategy(Strategy):
    """Retour a la moyenne en range.

    Marche sans direction (ADX bas), exces sur une bande de Bollinger, RSI en
    zone extreme, et une bougie de rejet. Objectif court (la moyenne mobile),
    stop au-dela de l'extreme : beaucoup de petits gains, quelques pertes plus
    larges. Le taux de reussite est eleve, l'esperance ne l'est pas
    automatiquement - d'ou le stop obligatoire.
    """

    name = "mean_reversion"
    label = "Retour a la moyenne (range)"
    description = "ADX bas + exces Bollinger + RSI extreme + bougie de rejet."

    def generate(self, symbol, ltf, htf) -> Optional[Signal]:
        cfg = self.cfg
        if len(ltf) < 3:
            return None
        cur, prev = ltf.iloc[-1], ltf.iloc[-2]
        if _isnan(
            cur.get("bb_low"), cur.get("bb_high"), cur.get("bb_mid"),
            cur.get("atr"), cur.get("adx"), cur.get("rsi"),
        ):
            return None
        if cur["adx"] > cfg.adx_range_max:
            return None
        if cfg.min_atr_points > 0 and cur["atr"] < cfg.min_atr_points:
            return None

        long_setup = (
            prev["low"] < prev["bb_low"]
            and cur["close"] > cur["bb_low"]
            and cur["close"] > cur["open"]
            and cur["rsi"] < 38.0
        )
        short_setup = (
            prev["high"] > prev["bb_high"]
            and cur["close"] < cur["bb_high"]
            and cur["close"] < cur["open"]
            and cur["rsi"] > 62.0
        )
        if not (long_setup or short_setup):
            return None
        side = Side.BUY if long_setup else Side.SELL

        entry = float(cur["close"])
        target = float(cur["bb_mid"])
        # L'objectif est la moyenne : si elle est deja franchie, pas de trade.
        if side is Side.BUY and target <= entry:
            return None
        if side is Side.SELL and target >= entry:
            return None

        atr_value = float(cur["atr"])
        if side is Side.BUY:
            stop = min(float(prev["low"]), float(cur["low"])) - atr_value * 0.5
        else:
            stop = max(float(prev["high"]), float(cur["high"])) + atr_value * 0.5
        risk = abs(entry - stop)
        reward = abs(target - entry)
        if risk <= 0 or reward / risk < cfg.mr_min_rr:
            return None

        score = 0.45
        score += 0.20 if cur["adx"] < cfg.adx_range_max - 4 else 0.0
        score += 0.20 if (cur["rsi"] < 30.0 or cur["rsi"] > 70.0) else 0.0
        score += 0.15 if abs(cur["close"] - cur["open"]) > atr_value * 0.35 else 0.0

        bande = "basse" if side is Side.BUY else "haute"
        reason = (
            f"Range (ADX {cur['adx']:.0f}), exces sous bande {bande} de Bollinger, "
            f"RSI {cur['rsi']:.0f}, retour vers la moyenne"
        )
        signal = Signal(
            symbol=symbol,
            side=side,
            entry=entry,
            stop_loss=stop,
            take_profit=target,
            confidence=max(0.0, min(1.0, score)),
            reason=reason,
            atr=atr_value,
            bar_time=ltf.index[-1],
        )
        return signal


class ConfluenceStrategy(Strategy):
    """Detecte le regime de marche puis delegue a la strategie adaptee.

    ADX >= seuil de tendance -> suivi de tendance.
    ADX <= seuil de range    -> retour a la moyenne.
    Entre les deux          -> aucune position (zone la plus couteuse).
    """

    name = "confluence"
    label = "Confluence (auto tendance/range)"
    description = "Choisit la logique selon le regime detecte par l'ADX."

    def __init__(self, cfg: StrategyConfig):
        super().__init__(cfg)
        self.trend = TrendPullbackStrategy(cfg)
        self.range_ = MeanReversionStrategy(cfg)

    def generate(self, symbol, ltf, htf) -> Optional[Signal]:
        if len(ltf) < 3:
            return None
        cur = ltf.iloc[-1]
        if _isnan(cur.get("adx")):
            return None
        if cur["adx"] >= self.cfg.adx_trend_min:
            return self.trend.generate(symbol, ltf, htf)
        if cur["adx"] <= self.cfg.adx_range_max:
            return self.range_.generate(symbol, ltf, htf)
        return None  # zone de transition : on s'abstient


STRATEGIES = {
    ConfluenceStrategy.name: ConfluenceStrategy,
    TrendPullbackStrategy.name: TrendPullbackStrategy,
    MeanReversionStrategy.name: MeanReversionStrategy,
}


def build_strategy(cfg: StrategyConfig) -> Strategy:
    cls = STRATEGIES.get(cfg.name, ConfluenceStrategy)
    return cls(cfg)

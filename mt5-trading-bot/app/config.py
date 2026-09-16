"""Configuration de l'application : dataclasses typees + persistance JSON.

Le fichier de config est stocke dans %APPDATA%/MT5TradingBot/config.json sous
Windows (ou ~/.config/mt5tradingbot ailleurs). Le mot de passe n'est jamais
ecrit en clair par defaut : il n'est conserve que si l'utilisateur coche
explicitement "memoriser".
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import asdict, dataclass, field, fields, is_dataclass
from pathlib import Path
from typing import Any, Dict, List

APP_NAME = "MT5TradingBot"


def app_data_dir() -> Path:
    """Repertoire de donnees de l'application, cree si absent."""
    if sys.platform.startswith("win"):
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support"
    else:
        base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    path = base / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


CONFIG_PATH = app_data_dir() / "config.json"
DB_PATH = app_data_dir() / "journal.sqlite3"
LOG_DIR = app_data_dir() / "logs"


@dataclass
class ConnectionConfig:
    """Parametres de connexion au terminal MetaTrader 5."""

    terminal_path: str = ""          # chemin vers terminal64.exe (vide = auto)
    login: int = 0
    server: str = ""
    password: str = ""               # vide si non memorise
    remember_password: bool = False
    # "demo" | "real" : garde-fou applicatif, verifie contre le vrai type de compte
    account_kind: str = "demo"
    # Mode hors-ligne : simulateur interne, aucun ordre reel. Utile pour tester
    # l'interface et les strategies sans terminal MT5 installe.
    offline_simulation: bool = False


@dataclass
class RiskConfig:
    """Garde-fous. Ce sont eux qui protegent le capital, pas la strategie."""

    risk_per_trade_pct: float = 0.5      # % de l'equity risque par trade
    max_daily_loss_pct: float = 2.0      # arret du jour si perte >= X% de l'equity de debut de journee
    max_drawdown_pct: float = 10.0       # kill switch definitif sur le pic d'equity
    max_open_positions: int = 3          # positions simultanees toutes paires confondues
    max_positions_per_symbol: int = 1
    max_trades_per_day: int = 10
    max_spread_points: int = 25          # spread max tolere, en points
    min_free_margin_pct: float = 30.0    # marge libre minimale exigee apres ouverture
    max_lot: float = 1.0                 # plafond dur sur le volume
    # Gestion de position
    breakeven_at_r: float = 1.0          # deplace le SL au point mort a +1R
    trailing_start_r: float = 1.5        # demarre le trailing a +1.5R
    trailing_atr_mult: float = 1.5       # distance du trailing, en ATR
    close_all_on_daily_stop: bool = True
    # Sessions (heure du serveur MT5, 0-23). Hors de ces plages : aucune entree.
    session_start_hour: int = 7
    session_end_hour: int = 20
    trade_monday: bool = True
    trade_tuesday: bool = True
    trade_wednesday: bool = True
    trade_thursday: bool = True
    trade_friday: bool = True
    friday_cutoff_hour: int = 18         # pas d'entree apres cette heure le vendredi


@dataclass
class StrategyConfig:
    """Parametres de la logique d'entree."""

    name: str = "confluence"             # confluence | trend_pullback | mean_reversion
    timeframe: str = "M15"               # unite de travail
    higher_timeframe: str = "H4"         # filtre de tendance
    bars: int = 600                      # profondeur d'historique chargee
    # Indicateurs
    ema_fast: int = 21
    ema_slow: int = 50
    ema_trend: int = 200
    rsi_period: int = 14
    atr_period: int = 14
    adx_period: int = 14
    adx_trend_min: float = 22.0          # au-dessus : marche directionnel
    adx_range_max: float = 18.0          # en dessous : marche en range
    bb_period: int = 20
    bb_std: float = 2.0
    # Sorties
    sl_atr_mult: float = 1.8
    tp_atr_mult: float = 2.7             # ratio R:R = tp/sl
    min_rr: float = 1.2
    # Le retour a la moyenne vise un objectif court : exiger le meme R:R que
    # le suivi de tendance reviendrait a ne jamais le declencher. Son taux de
    # reussite plus eleve compense un R:R plus faible - mais il faut alors
    # depasser 1/(1+R:R) de reussite pour etre a l'equilibre.
    mr_min_rr: float = 0.9
    # Filtres qualite
    min_atr_points: float = 0.0          # 0 = desactive ; evite les marches morts
    require_htf_alignment: bool = True   # l'unite superieure doit valider le sens
    cooldown_bars: int = 3               # bougies d'attente entre deux entrees sur un symbole


@dataclass
class TradingConfig:
    symbols: List[str] = field(default_factory=lambda: ["EURUSD", "GBPUSD", "USDJPY"])
    magic: int = 730144
    deviation_points: int = 20           # slippage max autorise
    poll_seconds: float = 2.0            # periode de la boucle moteur
    # Securite : tant que False, le moteur analyse et journalise mais n'envoie
    # aucun ordre. C'est la valeur par defaut, volontairement.
    live_orders_enabled: bool = False


@dataclass
class AppConfig:
    connection: ConnectionConfig = field(default_factory=ConnectionConfig)
    risk: RiskConfig = field(default_factory=RiskConfig)
    strategy: StrategyConfig = field(default_factory=StrategyConfig)
    trading: TradingConfig = field(default_factory=TradingConfig)

    # ---------------------------------------------------------------- IO ----
    def to_dict(self, include_secrets: bool = True) -> Dict[str, Any]:
        data = asdict(self)
        if not include_secrets or not self.connection.remember_password:
            data["connection"]["password"] = ""
        return data

    def save(self, path: Path = CONFIG_PATH) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        with tmp.open("w", encoding="utf-8") as fh:
            json.dump(self.to_dict(), fh, indent=2, ensure_ascii=False)
        tmp.replace(path)  # ecriture atomique : pas de config tronquee

    @classmethod
    def load(cls, path: Path = CONFIG_PATH) -> "AppConfig":
        cfg = cls()
        if not path.exists():
            return cfg
        try:
            with path.open("r", encoding="utf-8") as fh:
                raw = json.load(fh)
        except (json.JSONDecodeError, OSError):
            return cfg  # config corrompue : on repart sur les defauts
        return _merge_dataclass(cfg, raw)


def _merge_dataclass(instance: Any, raw: Dict[str, Any]) -> Any:
    """Applique `raw` sur `instance` en ignorant les cles inconnues.

    Tolerant aux anciennes versions de config : un champ absent garde sa
    valeur par defaut, un champ en trop est ignore, un type invalide est
    rejete plutot que de faire planter l'application au demarrage.
    """
    if not isinstance(raw, dict):
        return instance
    for f in fields(instance):
        if f.name not in raw:
            continue
        value = raw[f.name]
        current = getattr(instance, f.name)
        if is_dataclass(current) and not isinstance(current, type):
            _merge_dataclass(current, value)
            continue
        try:
            if isinstance(current, bool):
                setattr(instance, f.name, bool(value))
            elif isinstance(current, int) and not isinstance(value, bool):
                setattr(instance, f.name, int(value))
            elif isinstance(current, float):
                setattr(instance, f.name, float(value))
            elif isinstance(current, list):
                setattr(instance, f.name, [str(v) for v in value])
            elif isinstance(current, str):
                setattr(instance, f.name, str(value))
        except (TypeError, ValueError):
            continue
    return instance

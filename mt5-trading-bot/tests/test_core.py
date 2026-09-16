"""Tests du coeur metier (indicateurs, risque, strategies, backtest, moteur).

Lancement : python -m pytest tests -q
Aucun terminal MetaTrader 5 n'est necessaire : tout passe par le simulateur.
"""

from __future__ import annotations

import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import AppConfig, RiskConfig, StrategyConfig
from app.core import indicators as ind
from app.core.backtest import run_backtest
from app.core.engine import TradingEngine
from app.core.journal import Journal
from app.core.models import AccountSnapshot, Side, Signal, SymbolSpec
from app.core.risk import RiskManager, round_to_step
from app.core.simulator import SimulatedBroker
from app.core.strategies import STRATEGIES, build_strategy


# ------------------------------------------------------------- fixtures ----
def make_frame(n: int = 800, seed: int = 7, vol: float = 0.0004) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    close = 1.10 + np.cumsum(rng.normal(0, vol, n))
    index = pd.date_range("2024-01-01", periods=n, freq="15min")
    return pd.DataFrame(
        {
            "open": np.r_[close[0], close[:-1]],
            "high": close + np.abs(rng.normal(0, vol, n)),
            "low": close - np.abs(rng.normal(0, vol, n)),
            "close": close,
        },
        index=index,
    )


@pytest.fixture
def journal(tmp_path: Path) -> Journal:
    j = Journal(tmp_path / "journal.sqlite3")
    yield j
    j.close()


# ----------------------------------------------------------- indicateurs ---
def test_indicateurs_dans_leurs_bornes():
    enriched = ind.enrich(make_frame(), StrategyConfig())
    rsi = enriched["rsi"].dropna()
    assert (rsi >= 0).all() and (rsi <= 100).all()
    assert (enriched["atr"].dropna() >= 0).all()
    adx = enriched["adx"].dropna()
    assert (adx >= 0).all() and (adx <= 100).all()
    assert (enriched["bb_low"].dropna() <= enriched["bb_high"].dropna()).all()


def test_aucun_biais_de_look_ahead():
    """La valeur a l'instant t ne doit pas dependre des bougies futures."""
    df = make_frame()
    cfg = StrategyConfig()
    complet = ind.enrich(df, cfg)
    tronque = ind.enrich(df.iloc[:-50], cfg)
    cible = tronque.index[-1]
    for column in ("ema_fast", "rsi", "atr", "adx", "bb_mid"):
        a, b = complet.loc[cible, column], tronque.loc[cible, column]
        assert abs(a - b) < 1e-9, f"{column} change quand on ajoute des bougies futures"


# ---------------------------------------------------------------- risque ---
def test_volume_respecte_le_risque_demande():
    cfg = RiskConfig()
    cfg.risk_per_trade_pct = 0.5
    manager = RiskManager(cfg)
    account = AccountSnapshot(equity=10_000, balance=10_000, margin_free=10_000, leverage=100)
    spec = SymbolSpec("EURUSD", 5, 1e-5, 0.01, 50, 0.01, 1.0, 1e-5, 10)
    signal = Signal("EURUSD", Side.BUY, 1.1000, 1.0970, 1.1045, 0.7, "t")

    volume, error = manager.position_size(signal, spec, account)
    assert error == ""
    # 300 ticks a 1 USD le tick => 300 USD par lot ; on veut perdre 50 USD.
    perte_si_stop = (signal.risk_distance / spec.trade_tick_size) * spec.trade_tick_value * volume
    assert perte_si_stop <= 10_000 * 0.005 + 1e-6
    assert perte_si_stop > 10_000 * 0.005 * 0.9  # sans sous-dimensionner betement


def test_arrondi_du_volume_toujours_vers_le_bas():
    assert round_to_step(0.1699, 0.01) == 0.16
    assert round_to_step(1.99, 0.1) == 1.9
    assert round_to_step(0.004, 0.01) == 0.0


def test_volume_refuse_si_sous_le_minimum_broker():
    manager = RiskManager(RiskConfig())
    account = AccountSnapshot(equity=100, balance=100, margin_free=100, leverage=100)
    spec = SymbolSpec("EURUSD", 5, 1e-5, 0.10, 50, 0.10, 1.0, 1e-5, 10)
    signal = Signal("EURUSD", Side.BUY, 1.1000, 1.0900, 1.1150, 0.7, "t")
    volume, error = manager.position_size(signal, spec, account)
    assert volume == 0.0 and "minimum" in error


@pytest.mark.parametrize(
    "moment, attendu",
    [
        (datetime(2024, 5, 15, 10, tzinfo=timezone.utc), True),    # mercredi 10h
        (datetime(2024, 5, 15, 3, tzinfo=timezone.utc), False),    # nuit
        (datetime(2024, 5, 18, 10, tzinfo=timezone.utc), False),   # samedi
        (datetime(2024, 5, 17, 19, tzinfo=timezone.utc), False),   # vendredi soir
    ],
)
def test_filtre_de_session(moment, attendu):
    manager = RiskManager(RiskConfig())
    assert manager.session_open(moment)[0] is attendu


def test_coupe_circuit_perte_journaliere():
    manager = RiskManager(RiskConfig())        # limite par defaut : 2 %
    debut = AccountSnapshot(equity=10_000, balance=10_000)
    manager.start_session(debut, datetime(2024, 5, 15, 8, tzinfo=timezone.utc))
    assert manager.check_circuit_breakers(AccountSnapshot(equity=9_900)) is None
    assert manager.check_circuit_breakers(AccountSnapshot(equity=9_750)) is not None
    assert manager.halted


def test_coupe_circuit_drawdown_reste_actif_le_lendemain():
    """Le drawdown global ne doit pas se reinitialiser au changement de jour."""
    manager = RiskManager(RiskConfig())
    manager.start_session(AccountSnapshot(equity=10_000), datetime(2024, 5, 15, 8, tzinfo=timezone.utc))
    manager.check_circuit_breakers(AccountSnapshot(equity=8_500))   # -15 %
    assert manager.halted
    manager.roll_day_if_needed(AccountSnapshot(equity=8_500), datetime(2024, 5, 16, 8, tzinfo=timezone.utc))
    assert manager.halted, "le kill switch de drawdown doit survivre au changement de jour"


def test_stop_elargi_selon_la_distance_minimale_du_broker():
    manager = RiskManager(RiskConfig())
    spec = SymbolSpec("EURUSD", 5, 1e-5, 0.01, 50, 0.01, 1.0, 1e-5, 500)
    signal = Signal("EURUSD", Side.BUY, 1.1000, 1.0997, 1.10045, 0.7, "t")
    normalise = manager.normalize_stops(signal, spec, 1.1002)
    assert normalise.risk_distance >= 500 * spec.point
    assert normalise.rr == pytest.approx(signal.rr, rel=1e-6)   # le R:R est preserve


def test_refus_si_spread_trop_large():
    manager = RiskManager(RiskConfig())
    account = AccountSnapshot(equity=10_000, margin_free=10_000, leverage=100)
    manager.start_session(account, datetime(2024, 5, 15, 10, tzinfo=timezone.utc))
    spec = SymbolSpec("EURUSD", 5, 1e-5, 0.01, 50, 0.01, 1.0, 1e-5, 10)
    signal = Signal("EURUSD", Side.BUY, 1.1000, 1.0970, 1.1045, 0.7, "t")
    decision = manager.evaluate(
        signal, spec, account, [], datetime(2024, 5, 15, 10, tzinfo=timezone.utc), 99
    )
    assert not decision.approved and "Spread" in decision.reasons[0]


# ------------------------------------------------------------ strategies ---
@pytest.mark.parametrize("nom", list(STRATEGIES))
def test_signaux_coherents(nom):
    cfg = StrategyConfig()
    cfg.name = nom
    strategie = build_strategy(cfg)
    enriched = ind.enrich(make_frame(1500, seed=3), cfg)

    for i in range(300, len(enriched)):
        signal = strategie.generate("EURUSD", enriched.iloc[:i], enriched.iloc[:i])
        if signal is None:
            continue
        if signal.side is Side.BUY:
            assert signal.stop_loss < signal.entry < signal.take_profit
        else:
            assert signal.stop_loss > signal.entry > signal.take_profit
        assert signal.risk_distance > 0 and 0.0 <= signal.confidence <= 1.0


# -------------------------------------------------------------- backtest ---
def test_backtest_sur_marche_aleatoire_reste_proche_de_zero():
    """Sur du bruit pur, l'esperance doit tourner autour de 0 : sinon le
    moteur de backtest fabrique un avantage qui n'existe pas."""
    spec = SymbolSpec("EURUSD", 5, 1e-5, 0.01, 50, 0.01, 1.0, 1e-5, 10, spread=0)
    cfg_strategie, cfg_risque = StrategyConfig(), RiskConfig()
    cfg_risque.max_open_positions = 1

    resultats = []
    for seed in range(1, 7):
        m15 = make_frame(6000, seed=seed, vol=0.0004)
        resultat = run_backtest({"E": m15}, {"E": m15}, {"E": spec},
                                cfg_strategie, cfg_risque, 10_000.0)
        if resultat.trades:
            resultats.append(resultat.summary()["avg_r"])

    assert resultats, "aucun trade genere, le test ne prouve rien"
    assert abs(float(np.mean(resultats))) < 0.35, (
        f"R moyen {np.mean(resultats):.2f} : suspect sur un marche sans tendance"
    )


def test_backtest_sans_historique_ne_plante_pas():
    spec = SymbolSpec("EURUSD", 5, 1e-5, 0.01, 50, 0.01, 1.0, 1e-5, 10)
    resultat = run_backtest({"E": make_frame(30)}, {}, {"E": spec},
                            StrategyConfig(), RiskConfig(), 10_000.0)
    assert resultat.trades == [] and resultat.note


# --------------------------------------------------------------- journal ---
def test_statistiques_du_journal(journal: Journal):
    journal.record_open(1, "EURUSD", "BUY", 0.1, 1.10, 1.09, 1.11, "c", "r", 0.7, True)
    journal.record_close(1, 1.11, 60.0, "take-profit")
    journal.record_open(2, "GBPUSD", "SELL", 0.1, 1.27, 1.28, 1.26, "c", "r", 0.6, True)
    journal.record_close(2, 1.28, -30.0, "stop-loss")

    stats = journal.statistics()
    assert stats["trades"] == 2
    assert stats["win_rate"] == 50.0
    assert stats["profit_factor"] == pytest.approx(2.0)
    assert stats["net"] == pytest.approx(30.0)


# ---------------------------------------------------------------- moteur ---
def test_moteur_complet_sur_simulateur(journal: Journal):
    """Boucle complete : connexion, analyse, ordre, gestion, fermeture."""
    config = AppConfig()
    config.connection.offline_simulation = True
    config.trading.live_orders_enabled = True
    config.trading.poll_seconds = 0.02
    config.trading.symbols = ["EURUSD", "GBPUSD", "USDJPY"]
    config.risk.session_start_hour, config.risk.session_end_hour = 0, 23
    config.risk.friday_cutoff_hour = 23
    config.risk.max_trades_per_day = 500

    evenements = []
    moteur = TradingEngine(config, journal,
                           on_log=lambda n, c, s, m: evenements.append((n, c, m)))
    moteur.start()
    time.sleep(8)
    moteur.stop()

    erreurs = [e for e in evenements if e[0] == "ERROR"]
    assert not erreurs, f"erreurs pendant le cycle : {erreurs[:3]}"
    assert not moteur.running
    assert any(c == "moteur" for _, c, _ in evenements)


def test_moteur_refuse_le_reel_quand_le_demo_est_demande(journal: Journal):
    """Garde-fou : demander DEMO et tomber sur un compte reel doit bloquer."""
    config = AppConfig()
    config.connection.offline_simulation = True
    config.connection.account_kind = "demo"

    evenements = []
    moteur = TradingEngine(config, journal,
                           on_log=lambda n, c, s, m: evenements.append((n, c, m)))
    # On force le simulateur a se declarer "reel".
    original = SimulatedBroker.account

    def faux_compte(self):
        snapshot = original(self)
        snapshot.is_demo = False
        return snapshot

    SimulatedBroker.account = faux_compte
    try:
        moteur.start()
        time.sleep(1.5)
        moteur.stop()
    finally:
        SimulatedBroker.account = original

    refus = [m for n, c, m in evenements if n == "ERROR" and "SECURITE" in m]
    assert refus, "le moteur aurait du refuser de demarrer"


def test_mode_analyse_n_envoie_aucun_ordre(journal: Journal):
    config = AppConfig()
    config.connection.offline_simulation = True
    config.trading.live_orders_enabled = False      # mode analyse
    config.trading.poll_seconds = 0.02
    config.risk.session_start_hour, config.risk.session_end_hour = 0, 23
    config.risk.friday_cutoff_hour = 23

    moteur = TradingEngine(config, journal)
    moteur.start()
    time.sleep(5)
    broker = moteur.broker
    moteur.stop()

    assert broker.positions() == [], "aucune position ne doit etre ouverte en mode analyse"
    assert journal.statistics()["trades"] == 0


# ----------------------------------------------------------- configuration -
def test_config_tolere_un_fichier_corrompu(tmp_path: Path):
    chemin = tmp_path / "config.json"
    chemin.write_text("{ ceci n'est pas du json", encoding="utf-8")
    config = AppConfig.load(chemin)
    assert config.risk.risk_per_trade_pct == RiskConfig().risk_per_trade_pct


def test_config_ignore_les_champs_inconnus(tmp_path: Path):
    chemin = tmp_path / "config.json"
    chemin.write_text(
        '{"risk": {"risk_per_trade_pct": 1.25, "champ_invente": 42}, "inconnu": 1}',
        encoding="utf-8",
    )
    config = AppConfig.load(chemin)
    assert config.risk.risk_per_trade_pct == 1.25


def test_mot_de_passe_non_ecrit_sans_memorisation(tmp_path: Path):
    config = AppConfig()
    config.connection.password = "secret"
    config.connection.remember_password = False
    chemin = tmp_path / "config.json"
    config.save(chemin)
    assert "secret" not in chemin.read_text(encoding="utf-8")


def test_plafond_de_positions_respecte_dans_un_meme_cycle(journal: Journal):
    """Deux signaux traites dans le meme cycle ne doivent pas franchir le plafond.

    Sans inscription immediate de la position dans le cache du moteur, le second
    signal verrait encore zero position ouverte et passerait le controle.
    """
    config = AppConfig()
    config.connection.offline_simulation = True
    config.trading.live_orders_enabled = True
    config.risk.max_open_positions = 1          # le plafond que l'on teste
    config.risk.session_start_hour, config.risk.session_end_hour = 0, 23
    config.risk.friday_cutoff_hour = 23

    moteur = TradingEngine(config, journal)
    moteur.broker = SimulatedBroker()
    moteur.broker.connect(config.connection)
    maintenant = datetime(2024, 5, 15, 10, tzinfo=timezone.utc)
    compte = moteur.broker.account()
    moteur.risk.start_session(compte, maintenant)

    # Deux signaux valides sur deux symboles, comme en fin de cycle d'analyse.
    for symbole in ("EURUSD", "GBPUSD"):
        moteur.broker.ensure_symbol(symbole)
        spec = moteur.broker.symbol_spec(symbole)
        bid, ask, _ = moteur.broker.tick(symbole)
        signal = Signal(symbole, Side.BUY, ask, ask - 0.0030, ask + 0.0045, 0.8, "test")
        moteur._try_enter(signal, spec, compte, maintenant, spread_points=10)

    ouvertes = moteur.broker.positions(config.trading.magic)
    moteur.broker.shutdown()
    assert len(ouvertes) == 1, (
        f"{len(ouvertes)} positions ouvertes pour un plafond de 1 : "
        "le second signal n'a pas vu la position du premier"
    )

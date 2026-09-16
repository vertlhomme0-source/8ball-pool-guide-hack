"""Pont entre le moteur (thread metier) et l'interface (thread Qt).

Le moteur appelle des callbacks depuis son propre thread. Emettre un signal Qt
depuis un autre thread est sur : Qt met l'appel en file et le livre dans le
thread du destinataire. C'est la seule facon correcte de toucher l'interface
depuis le moteur - aucun widget n'est manipule directement ici.
"""

from __future__ import annotations

from typing import List, Optional

from PySide6.QtCore import QObject, Signal

from ..config import AppConfig
from ..core.engine import TradingEngine
from ..core.journal import Journal
from ..core.models import EngineStats, PositionInfo


class EngineBridge(QObject):
    log_received = Signal(str, str, str, str)      # niveau, categorie, symbole, message
    stats_updated = Signal(object)                 # EngineStats
    positions_updated = Signal(object)             # List[PositionInfo]
    state_changed = Signal(bool)                   # moteur en marche ?

    def __init__(self, config: AppConfig, journal: Journal, parent: Optional[QObject] = None):
        super().__init__(parent)
        self.config = config
        self.journal = journal
        self.engine: Optional[TradingEngine] = None

    # ------------------------------------------------------------ pilotage --
    def start(self) -> None:
        if self.engine is not None and self.engine.running:
            return
        self.engine = TradingEngine(
            self.config,
            self.journal,
            on_log=self._on_log,
            on_stats=self._on_stats,
            on_positions=self._on_positions,
        )
        self.engine.start()
        self.state_changed.emit(True)

    def stop(self) -> None:
        if self.engine is not None:
            self.engine.stop()
        self.state_changed.emit(False)

    def close_all(self) -> None:
        if self.engine is not None and self.engine.running:
            self.engine.request_close_all()

    def close_position(self, ticket: int) -> None:
        if self.engine is not None and self.engine.running:
            self.engine.request_close(ticket)

    def halt(self, reason: str = "Arret d'urgence manuel") -> None:
        if self.engine is not None:
            self.engine.request_halt(reason)

    def resume(self) -> None:
        if self.engine is not None:
            self.engine.resume()

    @property
    def running(self) -> bool:
        return self.engine is not None and self.engine.running

    # ----------------------------------------------------------- callbacks --
    def _on_log(self, level: str, category: str, symbol: str, message: str) -> None:
        self.log_received.emit(level, category, symbol, message)

    def _on_stats(self, stats: EngineStats) -> None:
        self.stats_updated.emit(stats)
        # Le moteur peut s'arreter tout seul (echec de connexion, coupe-circuit) :
        # l'interface doit suivre cet etat sans le deviner.
        if not stats.running:
            self.state_changed.emit(False)

    def _on_positions(self, positions: List[PositionInfo]) -> None:
        self.positions_updated.emit(positions)

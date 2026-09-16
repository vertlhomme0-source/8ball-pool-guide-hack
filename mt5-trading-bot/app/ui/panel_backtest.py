"""Onglet Backtest : rejoue la strategie sur l'historique du broker."""

from __future__ import annotations

import copy
from typing import Optional

from PySide6.QtCore import QObject, QThread, Qt, Signal
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (
    QAbstractItemView, QComboBox, QFormLayout, QGridLayout, QHBoxLayout, QHeaderView,
    QLabel, QLineEdit, QMessageBox, QProgressBar, QPushButton, QSpinBox,
    QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget,
)

from ..config import AppConfig
from ..core.backtest import BacktestResult, run_backtest
from ..core.broker import TIMEFRAMES, BrokerError, MT5Broker
from ..core.simulator import SimulatedBroker
from . import theme
from .widgets import Card, SparklineChart, StatCard, section_title, signed_money


class BacktestWorker(QObject):
    """Execute le backtest hors du thread graphique."""

    progress = Signal(int, int)
    finished = Signal(object)          # BacktestResult
    failed = Signal(str)

    def __init__(self, config: AppConfig, symbols: list[str], bars: int):
        super().__init__()
        self.config = config
        self.symbols = symbols
        self.bars = bars
        self._cancel = False

    def cancel(self) -> None:
        self._cancel = True

    def run(self) -> None:
        broker = None
        try:
            conn = self.config.connection
            broker = SimulatedBroker() if conn.offline_simulation else MT5Broker()
            ok, message = broker.connect(conn)
            if not ok:
                self.failed.emit(message)
                return

            scfg = self.config.strategy
            data, htf_data, specs = {}, {}, {}
            for symbol in self.symbols:
                if self._cancel:
                    self.failed.emit("Backtest annule.")
                    return
                if not broker.ensure_symbol(symbol):
                    continue
                spec = broker.symbol_spec(symbol)
                if spec is None:
                    continue
                ltf = broker.rates(symbol, scfg.timeframe, self.bars)
                if ltf is None or ltf.empty:
                    continue
                # Assez de profondeur pour que l'unite superieure ait ses EMA.
                htf_count = max(300, int(self.bars * TIMEFRAMES.get(scfg.timeframe, 15)
                                         / max(1, TIMEFRAMES.get(scfg.higher_timeframe, 240))) + 250)
                htf = broker.rates(symbol, scfg.higher_timeframe, htf_count)
                data[symbol] = ltf
                if htf is not None:
                    htf_data[symbol] = htf
                specs[symbol] = spec

            if not data:
                self.failed.emit(
                    "Aucune donnee recuperee. Verifiez que les symboles existent "
                    "dans le Market Watch du terminal."
                )
                return

            balance = 10_000.0
            account = broker.account()
            if account is not None and account.balance > 0:
                balance = account.balance

            def on_progress(current: int, total: int) -> bool:
                self.progress.emit(current, total)
                return not self._cancel

            result = run_backtest(
                data, htf_data, specs, self.config.strategy, self.config.risk,
                balance, progress=on_progress,
            )
            self.finished.emit(result)
        except BrokerError as exc:
            self.failed.emit(str(exc))
        except Exception as exc:
            self.failed.emit(f"{type(exc).__name__}: {exc}")
        finally:
            if broker is not None:
                try:
                    broker.shutdown()
                except Exception:
                    pass


class BacktestPanel(QWidget):
    def __init__(self, config: AppConfig, parent: Optional[QWidget] = None):
        super().__init__(parent)
        self.config = config
        self._thread: Optional[QThread] = None
        self._worker: Optional[BacktestWorker] = None
        self._build()

    # ------------------------------------------------------------ montage ---
    def _build(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(4, 4, 4, 4)
        layout.setSpacing(12)

        layout.addWidget(section_title(
            "Backtest",
            "Rejoue la strategie sur l'historique du broker, avec les memes regles de "
            "risque. Hypothese pessimiste : si le stop et l'objectif sont touches dans "
            "la meme bougie, la perte est comptee.",
        ))

        controls = Card(margins=14)
        row = QHBoxLayout()
        row.setSpacing(14)

        self.symbols = QLineEdit(", ".join(self.config.trading.symbols))
        self.symbols.setMinimumWidth(240)
        self.bars = QSpinBox()
        self.bars.setRange(300, 100_000)
        self.bars.setSingleStep(500)
        self.bars.setValue(5000)
        self.bars.setSuffix(" bougies")

        for label, widget in (("Symboles", self.symbols), ("Profondeur", self.bars)):
            holder = QWidget()
            form = QFormLayout(holder)
            form.setContentsMargins(0, 0, 0, 0)
            form.addRow(label, widget)
            row.addWidget(holder)

        self.timeframe_label = QLabel()
        self.timeframe_label.setProperty("role", "muted")
        row.addWidget(self.timeframe_label)
        row.addStretch(1)

        self.run_button = QPushButton("Lancer le backtest")
        self.run_button.setProperty("kind", "primary")
        self.run_button.clicked.connect(self._start)
        self.cancel_button = QPushButton("Annuler")
        self.cancel_button.setEnabled(False)
        self.cancel_button.clicked.connect(self._cancel)
        row.addWidget(self.run_button)
        row.addWidget(self.cancel_button)
        controls.body().addLayout(row)

        self.progress = QProgressBar()
        self.progress.setVisible(False)
        controls.body().addWidget(self.progress)
        layout.addWidget(controls)

        # Cartes de resultat
        stats_row = QHBoxLayout()
        stats_row.setSpacing(12)
        self.cards = {
            "trades": StatCard("Trades"),
            "win_rate": StatCard("Taux de reussite"),
            "profit_factor": StatCard("Facteur de profit"),
            "net": StatCard("Resultat net"),
            "max_drawdown_pct": StatCard("Drawdown max"),
            "max_consec_losses": StatCard("Pertes d'affilee"),
        }
        for card in self.cards.values():
            stats_row.addWidget(card)
        layout.addLayout(stats_row)

        chart_card = Card(margins=12)
        chart_card.body().addWidget(QLabel("Courbe de capital"))
        self.chart = SparklineChart()
        chart_card.body().addWidget(self.chart)
        layout.addWidget(chart_card, 1)

        self.note = QLabel()
        self.note.setWordWrap(True)
        self.note.setProperty("role", "muted")
        layout.addWidget(self.note)

        self.table = QTableWidget(0, 8)
        self.table.setHorizontalHeaderLabels(
            ["Symbole", "Sens", "Entree", "Sortie", "Volume", "Resultat", "R", "Issue"]
        )
        self.table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setAlternatingRowColors(True)
        self.table.verticalHeader().setVisible(False)
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        layout.addWidget(self.table, 1)

        self.refresh_labels()

    def refresh_labels(self) -> None:
        s = self.config.strategy
        self.timeframe_label.setText(
            f"Unite {s.timeframe} - tendance {s.higher_timeframe} - "
            f"logique « {s.name} » - risque {self.config.risk.risk_per_trade_pct} %/trade"
        )

    # ----------------------------------------------------------- execution --
    def _start(self) -> None:
        if self._thread is not None:
            return
        raw = self.symbols.text().replace(";", ",").replace(" ", ",")
        symbols = [s.strip().upper() for s in raw.split(",") if s.strip()]
        if not symbols:
            QMessageBox.warning(self, "Backtest", "Indiquez au moins un symbole.")
            return

        self.run_button.setEnabled(False)
        self.cancel_button.setEnabled(True)
        self.progress.setVisible(True)
        self.progress.setRange(0, 0)   # indetermine le temps du chargement
        self.note.setText("Chargement de l'historique...")

        # La configuration est copiee : modifier les parametres pendant le
        # backtest ne doit pas changer le calcul en cours.
        self._thread = QThread(self)
        self._worker = BacktestWorker(copy.deepcopy(self.config), symbols, self.bars.value())
        self._worker.moveToThread(self._thread)
        self._thread.started.connect(self._worker.run)
        self._worker.progress.connect(self._on_progress)
        self._worker.finished.connect(self._on_finished)
        self._worker.failed.connect(self._on_failed)
        self._thread.start()

    def _cancel(self) -> None:
        if self._worker is not None:
            self._worker.cancel()
            self.note.setText("Annulation en cours...")

    def _cleanup(self) -> None:
        if self._thread is not None:
            self._thread.quit()
            self._thread.wait(5000)
            self._thread.deleteLater()
        self._thread = None
        self._worker = None
        self.run_button.setEnabled(True)
        self.cancel_button.setEnabled(False)
        self.progress.setVisible(False)

    def _on_progress(self, current: int, total: int) -> None:
        if total > 0:
            self.progress.setRange(0, total)
            self.progress.setValue(current)
            self.note.setText(f"Analyse : {current:,} / {total:,} bougies".replace(",", " "))

    def _on_failed(self, message: str) -> None:
        self._cleanup()
        self.note.setText(message)
        self.note.setStyleSheet(f"color: {theme.AMBER};")

    def _on_finished(self, result: BacktestResult) -> None:
        self._cleanup()
        self._render(result)

    # ------------------------------------------------------------ rendu -----
    def _render(self, result: BacktestResult) -> None:
        summary = result.summary()
        self.cards["trades"].set_value(str(summary["trades"]))
        self.cards["trades"].set_hint(f"{result.bars_tested:,} bougies testees".replace(",", " "))

        win_rate = summary["win_rate"]
        self.cards["win_rate"].set_value(
            f"{win_rate:.1f} %",
            theme.GREEN if win_rate >= 50 else (theme.AMBER if win_rate >= 35 else theme.RED),
        )
        self.cards["win_rate"].set_hint(f"{summary['wins']} gains / {summary['losses']} pertes")

        pf = summary["profit_factor"]
        pf_text = "∞" if pf == float("inf") else f"{pf:.2f}"
        self.cards["profit_factor"].set_value(
            pf_text, theme.GREEN if pf >= 1.3 else (theme.AMBER if pf >= 1.0 else theme.RED)
        )
        self.cards["profit_factor"].set_hint("gains bruts / pertes brutes")

        net = summary["net"]
        self.cards["net"].set_value(
            signed_money(net), theme.GREEN if net > 0 else theme.RED
        )
        self.cards["net"].set_hint(f"{summary['return_pct']:+.2f} % du capital")

        dd = summary["max_drawdown_pct"]
        self.cards["max_drawdown_pct"].set_value(
            f"{dd:.2f} %", theme.GREEN if dd < 10 else (theme.AMBER if dd < 20 else theme.RED)
        )
        self.cards["max_drawdown_pct"].set_hint("plus forte baisse du capital")

        streak = summary["max_consec_losses"]
        self.cards["max_consec_losses"].set_value(str(streak))
        self.cards["max_consec_losses"].set_hint(
            f"soit environ {streak * self.config.risk.risk_per_trade_pct:.1f} % de perte"
        )

        if result.equity:
            labels = [t.strftime("%d/%m") for t in result.times] if result.times else []
            self.chart.set_series(result.equity, labels, baseline=result.start_balance)

        self.table.setRowCount(0)
        for trade in result.trades[-500:]:
            row = self.table.rowCount()
            self.table.insertRow(row)
            color = theme.GREEN if trade.profit > 0 else theme.RED
            cells = [
                trade.symbol,
                trade.side,
                f"{trade.entry:.5f}".rstrip("0").rstrip("."),
                f"{trade.exit:.5f}".rstrip("0").rstrip("."),
                f"{trade.volume:g}",
                signed_money(trade.profit),
                f"{trade.r_multiple:+.2f}",
                trade.outcome,
            ]
            for column, text in enumerate(cells):
                item = QTableWidgetItem(text)
                if column in (5, 6):
                    item.setForeground(QColor(color))
                if column >= 2:
                    item.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
                item.setToolTip(trade.reason)
                self.table.setItem(row, column, item)
        self.table.scrollToBottom()

        note = result.note or (
            "Rappel : un backtest ne garantit rien. Verifiez que le nombre de trades "
            "est suffisant (au moins quelques centaines) avant d'en tirer une conclusion."
        )
        self.note.setText(note)
        self.note.setStyleSheet(f"color: {theme.TEXT_MUTED};")

    def shutdown(self) -> None:
        """Arrete proprement un backtest en cours a la fermeture de la fenetre."""
        if self._worker is not None:
            self._worker.cancel()
        if self._thread is not None:
            self._thread.quit()
            self._thread.wait(5000)

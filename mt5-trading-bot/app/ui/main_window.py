"""Fenetre principale : en-tete de pilotage + onglets."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import List, Optional

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QColor, QFont
from PySide6.QtWidgets import (
    QAbstractItemView, QComboBox, QHBoxLayout, QHeaderView, QLabel, QMainWindow,
    QMessageBox, QPlainTextEdit, QPushButton, QSplitter, QTabWidget,
    QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget,
)

from ..config import AppConfig
from ..core.journal import Journal
from ..core.models import EngineStats, PositionInfo
from . import theme
from .engine_bridge import EngineBridge
from .panel_backtest import BacktestPanel
from .panel_settings import SettingsPanel
from .widgets import (
    Badge, Card, SparklineChart, StatCard, money, pnl_color, section_title, signed_money,
)

LOG_LIMIT = 3000


class MainWindow(QMainWindow):
    def __init__(self, config: AppConfig, journal: Journal):
        super().__init__()
        self.config = config
        self.journal = journal
        self.bridge = EngineBridge(config, journal, self)
        self._last_stats: Optional[EngineStats] = None

        self.setWindowTitle("MT5 Trading Bot")
        self.resize(1360, 880)
        self.setMinimumSize(1080, 700)

        root = QWidget()
        root.setObjectName("Root")
        layout = QVBoxLayout(root)
        layout.setContentsMargins(16, 14, 16, 10)
        layout.setSpacing(12)
        layout.addWidget(self._build_header())
        layout.addWidget(self._build_tabs(), 1)
        self.setCentralWidget(root)

        self.statusBar().showMessage("Pret.")

        self.bridge.log_received.connect(self._on_log)
        self.bridge.stats_updated.connect(self._on_stats)
        self.bridge.positions_updated.connect(self._on_positions)
        self.bridge.state_changed.connect(self._on_state)

        # Rafraichissement des vues alimentees par le journal (donnees en base,
        # pas de signal temps reel a leur sujet).
        self._timer = QTimer(self)
        self._timer.timeout.connect(self._refresh_journal_views)
        self._timer.start(4000)

        self._load_history()
        self._refresh_journal_views()
        self._on_state(False)

    # ============================================================ en-tete ====
    def _build_header(self) -> QWidget:
        card = Card(margins=14, spacing=12)
        row = QHBoxLayout()
        row.setSpacing(14)

        title_box = QVBoxLayout()
        title_box.setSpacing(2)
        title = QLabel("MT5 Trading Bot")
        title.setProperty("role", "h1")
        self.account_line = QLabel("Aucun compte connecte")
        self.account_line.setProperty("role", "muted")
        title_box.addWidget(title)
        title_box.addWidget(self.account_line)
        row.addLayout(title_box)
        row.addSpacing(10)

        self.state_badge = Badge("ARRETE", theme.TEXT_MUTED)
        self.account_badge = Badge("—", theme.TEXT_MUTED)
        self.mode_badge = Badge("MODE ANALYSE", theme.ACCENT)
        for badge in (self.state_badge, self.account_badge, self.mode_badge):
            row.addWidget(badge, 0, Qt.AlignVCenter)
        row.addStretch(1)

        self.start_button = QPushButton("Demarrer")
        self.start_button.setProperty("kind", "primary")
        self.start_button.clicked.connect(self._start)
        self.stop_button = QPushButton("Arreter")
        self.stop_button.clicked.connect(self._stop)
        self.close_all_button = QPushButton("Tout fermer")
        self.close_all_button.clicked.connect(self._close_all)
        self.panic_button = QPushButton("Arret d'urgence")
        self.panic_button.setProperty("kind", "danger")
        self.panic_button.setToolTip(
            "Bloque toute nouvelle entree et ferme les positions ouvertes du bot."
        )
        self.panic_button.clicked.connect(self._panic)
        for button in (self.start_button, self.stop_button,
                       self.close_all_button, self.panic_button):
            row.addWidget(button)
        card.body().addLayout(row)

        self.halt_banner = QLabel()
        self.halt_banner.setWordWrap(True)
        self.halt_banner.setVisible(False)
        self.halt_banner.setStyleSheet(
            f"background: {theme.PANEL_HI}; border: 1px solid {theme.RED};"
            f" border-radius: 8px; padding: 8px; color: {theme.RED}; font-weight: 600;"
        )
        card.body().addWidget(self.halt_banner)
        return card

    # ============================================================= onglets ===
    def _build_tabs(self) -> QTabWidget:
        tabs = QTabWidget()
        tabs.addTab(self._build_dashboard(), "Tableau de bord")
        tabs.addTab(self._build_positions(), "Positions")
        tabs.addTab(self._build_journal(), "Journal")

        self.backtest_panel = BacktestPanel(self.config, self)
        tabs.addTab(self.backtest_panel, "Backtest")

        self.settings_panel = SettingsPanel(self.config, self)
        self.settings_panel.set_running_probe(lambda: self.bridge.running)
        self.settings_panel.applied.connect(self._on_settings_applied)
        tabs.addTab(self.settings_panel, "Parametres")
        return tabs

    # ------------------------------------------------------ tableau de bord --
    def _build_dashboard(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(4, 8, 4, 4)
        layout.setSpacing(12)

        cards = QHBoxLayout()
        cards.setSpacing(12)
        self.card_equity = StatCard("Equity", "—", "capital instantane")
        self.card_balance = StatCard("Solde", "—", "positions fermees")
        self.card_pnl = StatCard("P&L du jour", "—", "depuis l'ouverture")
        self.card_positions = StatCard("Positions", "0", "ouvertes par le bot")
        self.card_trades = StatCard("Trades du jour", "0", "quota journalier")
        self.card_drawdown = StatCard("Drawdown", "0.00 %", "depuis le pic")
        for card in (self.card_equity, self.card_balance, self.card_pnl,
                     self.card_positions, self.card_trades, self.card_drawdown):
            cards.addWidget(card)
        layout.addLayout(cards)

        splitter = QSplitter(Qt.Horizontal)

        chart_card = Card(margins=12)
        chart_card.body().addWidget(section_title(
            "Courbe de capital", "Releve toutes les minutes pendant que le moteur tourne."
        ))
        self.equity_chart = SparklineChart()
        chart_card.body().addWidget(self.equity_chart)
        splitter.addWidget(chart_card)

        stats_card = Card(margins=12)
        stats_card.body().addWidget(section_title(
            "Resultats enregistres", "Trades clotures par le bot, toutes sessions confondues."
        ))
        self.stats_table = QTableWidget(0, 2)
        self.stats_table.horizontalHeader().setVisible(False)
        self.stats_table.verticalHeader().setVisible(False)
        self.stats_table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.stats_table.setSelectionMode(QAbstractItemView.NoSelection)
        self.stats_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.stats_table.setShowGrid(False)
        stats_card.body().addWidget(self.stats_table)
        splitter.addWidget(stats_card)

        splitter.setStretchFactor(0, 3)
        splitter.setStretchFactor(1, 2)
        layout.addWidget(splitter, 1)

        activity_card = Card(margins=12)
        activity_card.body().addWidget(section_title("Activite recente"))
        self.activity_view = QPlainTextEdit()
        self.activity_view.setReadOnly(True)
        self.activity_view.setMaximumBlockCount(200)
        self.activity_view.setMaximumHeight(150)
        self.activity_view.setFont(QFont("Consolas", 9))
        activity_card.body().addWidget(self.activity_view)
        layout.addWidget(activity_card)
        return page

    # ----------------------------------------------------------- positions --
    def _build_positions(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(4, 8, 4, 4)
        layout.setSpacing(12)

        header = QHBoxLayout()
        header.addWidget(section_title(
            "Positions ouvertes",
            "Seules les positions portant le magic number du bot sont listees et gerees.",
        ))
        header.addStretch(1)
        self.close_selected_button = QPushButton("Fermer la selection")
        self.close_selected_button.clicked.connect(self._close_selected)
        header.addWidget(self.close_selected_button)
        layout.addLayout(header)

        self.positions_table = QTableWidget(0, 9)
        self.positions_table.setHorizontalHeaderLabels(
            ["Ticket", "Symbole", "Sens", "Volume", "Entree", "Actuel", "SL", "TP", "P&L"]
        )
        self.positions_table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.positions_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.positions_table.setAlternatingRowColors(True)
        self.positions_table.verticalHeader().setVisible(False)
        self.positions_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        layout.addWidget(self.positions_table, 1)

        layout.addWidget(section_title("Historique des trades du bot"))
        self.trades_table = QTableWidget(0, 8)
        self.trades_table.setHorizontalHeaderLabels(
            ["Ouvert le", "Symbole", "Sens", "Volume", "Entree", "Sortie", "Resultat", "Motif"]
        )
        self.trades_table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.trades_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.trades_table.setAlternatingRowColors(True)
        self.trades_table.verticalHeader().setVisible(False)
        self.trades_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        layout.addWidget(self.trades_table, 1)
        return page

    # ------------------------------------------------------------- journal --
    def _build_journal(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(4, 8, 4, 4)
        layout.setSpacing(10)

        header = QHBoxLayout()
        header.addWidget(section_title(
            "Journal", "Chaque decision du moteur est tracee, y compris les signaux refuses."
        ))
        header.addStretch(1)
        header.addWidget(QLabel("Niveau :"))
        self.level_filter = QComboBox()
        self.level_filter.addItems(["Tous", "INFO", "WARN", "ERROR"])
        self.level_filter.currentTextChanged.connect(lambda _: self._reload_logs())
        header.addWidget(self.level_filter)
        clear = QPushButton("Vider l'affichage")
        clear.setProperty("kind", "ghost")
        clear.clicked.connect(lambda: self.log_view.clear())
        header.addWidget(clear)
        layout.addLayout(header)

        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        self.log_view.setMaximumBlockCount(LOG_LIMIT)
        self.log_view.setFont(QFont("Consolas", 9))
        layout.addWidget(self.log_view, 1)
        return page

    # ========================================================== pilotage =====
    def _start(self) -> None:
        if self.bridge.running:
            return
        conn = self.config.connection
        if conn.account_kind == "real" and self.config.trading.live_orders_enabled \
                and not conn.offline_simulation:
            answer = QMessageBox.warning(
                self, "Compte reel",
                "Le moteur va demarrer sur un COMPTE REEL avec l'envoi d'ordres active.\n\n"
                f"Risque par trade : {self.config.risk.risk_per_trade_pct} %\n"
                f"Perte maximale du jour : {self.config.risk.max_daily_loss_pct} %\n"
                f"Drawdown maximal : {self.config.risk.max_drawdown_pct} %\n\n"
                "Confirmer le demarrage ?",
                QMessageBox.Yes | QMessageBox.Cancel, QMessageBox.Cancel,
            )
            if answer != QMessageBox.Yes:
                return
        self.log_view.appendHtml(
            f'<span style="color:{theme.TEXT_MUTED}">--- demarrage du moteur ---</span>'
        )
        self.bridge.start()

    def _stop(self) -> None:
        if not self.bridge.running:
            return
        if self._last_stats and self._last_stats.open_positions > 0:
            answer = QMessageBox.question(
                self, "Arreter le moteur",
                f"{self._last_stats.open_positions} position(s) sont encore ouvertes.\n"
                "Elles resteront ouvertes chez le broker et ne seront plus gerees "
                "(ni point mort, ni stop suiveur).\n\nArreter quand meme ?",
                QMessageBox.Yes | QMessageBox.Cancel, QMessageBox.Cancel,
            )
            if answer != QMessageBox.Yes:
                return
        self.bridge.stop()

    def _close_all(self) -> None:
        if not self.bridge.running:
            QMessageBox.information(self, "Moteur arrete",
                                    "Demarrez le moteur pour piloter les positions.")
            return
        answer = QMessageBox.question(
            self, "Tout fermer",
            "Fermer toutes les positions ouvertes par le bot au prix du marche ?",
            QMessageBox.Yes | QMessageBox.Cancel, QMessageBox.Cancel,
        )
        if answer == QMessageBox.Yes:
            self.bridge.close_all()

    def _panic(self) -> None:
        answer = QMessageBox.warning(
            self, "Arret d'urgence",
            "Le bot va bloquer toute nouvelle entree et fermer ses positions.\n"
            "Il faudra le relancer manuellement.\n\nConfirmer ?",
            QMessageBox.Yes | QMessageBox.Cancel, QMessageBox.Cancel,
        )
        if answer != QMessageBox.Yes:
            return
        self.bridge.halt("Arret d'urgence declenche depuis l'interface")
        self.bridge.close_all()

    def _close_selected(self) -> None:
        rows = {index.row() for index in self.positions_table.selectedIndexes()}
        if not rows:
            QMessageBox.information(self, "Positions",
                                    "Selectionnez au moins une ligne a fermer.")
            return
        if not self.bridge.running:
            QMessageBox.information(self, "Moteur arrete",
                                    "Demarrez le moteur pour piloter les positions.")
            return
        tickets = []
        for row in rows:
            item = self.positions_table.item(row, 0)
            if item is not None:
                tickets.append(int(item.text()))
        if not tickets:
            return
        answer = QMessageBox.question(
            self, "Fermer",
            f"Fermer {len(tickets)} position(s) au prix du marche ?",
            QMessageBox.Yes | QMessageBox.Cancel, QMessageBox.Cancel,
        )
        if answer != QMessageBox.Yes:
            return
        for ticket in tickets:
            self.bridge.close_position(ticket)

    def _on_settings_applied(self) -> None:
        self.backtest_panel.refresh_labels()
        self._update_mode_badge()

    # =========================================================== reactions ===
    def _on_state(self, running: bool) -> None:
        self.start_button.setEnabled(not running)
        self.stop_button.setEnabled(running)
        self.close_all_button.setEnabled(running)
        if running:
            self.state_badge.set_state("EN MARCHE", theme.GREEN)
        else:
            self.state_badge.set_state("ARRETE", theme.TEXT_MUTED)
            self.halt_banner.setVisible(False)
        self._update_mode_badge()

    def _update_mode_badge(self) -> None:
        conn, trading = self.config.connection, self.config.trading
        if conn.offline_simulation:
            self.mode_badge.set_state(
                "ORDRES SIMULES" if trading.live_orders_enabled else "MODE ANALYSE",
                theme.PURPLE,
            )
        elif not trading.live_orders_enabled:
            self.mode_badge.set_state("MODE ANALYSE", theme.ACCENT)
        elif conn.account_kind == "real":
            self.mode_badge.set_state("ORDRES REELS", theme.RED)
        else:
            self.mode_badge.set_state("ORDRES DEMO", theme.GREEN)

    def _on_stats(self, stats: EngineStats) -> None:
        self._last_stats = stats
        account = stats.account
        currency = account.currency or ""

        self.card_equity.set_value(money(account.equity, currency))
        self.card_equity.set_hint(f"marge libre {money(account.margin_free, currency)}")
        self.card_balance.set_value(money(account.balance, currency))
        self.card_balance.set_hint(f"levier 1:{account.leverage}" if account.leverage else "")

        self.card_pnl.set_value(signed_money(stats.pnl_today, currency),
                                pnl_color(stats.pnl_today))
        if stats.day_start_equity > 0:
            pct = stats.pnl_today / stats.day_start_equity * 100.0
            limit = self.config.risk.max_daily_loss_pct
            self.card_pnl.set_hint(f"{pct:+.2f} % / limite {limit:.2f} %")

        self.card_positions.set_value(str(stats.open_positions))
        self.card_positions.set_hint(f"maximum {self.config.risk.max_open_positions}")
        self.card_trades.set_value(str(stats.trades_today))
        self.card_trades.set_hint(f"maximum {self.config.risk.max_trades_per_day} / jour")

        dd = stats.drawdown_pct
        self.card_drawdown.set_value(
            f"{dd:.2f} %",
            theme.GREEN if dd < 3 else (theme.AMBER if dd < self.config.risk.max_drawdown_pct * 0.7
                                        else theme.RED),
        )
        self.card_drawdown.set_hint(f"arret a {self.config.risk.max_drawdown_pct:.2f} %")

        if stats.connected and account.login:
            kind = "DEMO" if account.is_demo else "REEL"
            colour = theme.GREEN if account.is_demo else theme.RED
            if self.config.connection.offline_simulation:
                kind, colour = "SIMULE", theme.PURPLE
            self.account_badge.set_state(kind, colour)
            self.account_line.setText(
                f"Compte {account.login} - {account.server} - {account.name or 'sans nom'}"
            )
        else:
            self.account_badge.set_state("—", theme.TEXT_MUTED)

        if stats.halted and stats.halt_reason:
            self.halt_banner.setText(f"MOTEUR SUSPENDU : {stats.halt_reason}")
            self.halt_banner.setVisible(True)
        else:
            self.halt_banner.setVisible(False)

        parts = []
        if stats.last_cycle:
            parts.append(f"dernier cycle {stats.last_cycle.strftime('%H:%M:%S')} UTC")
        if stats.last_error:
            parts.append(f"derniere erreur : {stats.last_error}")
        self.statusBar().showMessage(" | ".join(parts) or "Pret.")

    def _on_positions(self, positions: List[PositionInfo]) -> None:
        self.positions_table.setRowCount(len(positions))
        for row, pos in enumerate(positions):
            digits = 5 if pos.price_open < 50 else 3
            cells = [
                str(pos.ticket), pos.symbol, pos.side.value, f"{pos.volume:g}",
                f"{pos.price_open:.{digits}f}", f"{pos.price_current:.{digits}f}",
                f"{pos.sl:.{digits}f}" if pos.sl else "—",
                f"{pos.tp:.{digits}f}" if pos.tp else "—",
                signed_money(pos.profit),
            ]
            for column, text in enumerate(cells):
                item = QTableWidgetItem(text)
                if column >= 3:
                    item.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
                if column == 2:
                    item.setForeground(QColor(theme.GREEN if pos.side.value == "BUY" else theme.RED))
                if column == 8:
                    item.setForeground(QColor(pnl_color(pos.profit)))
                self.positions_table.setItem(row, column, item)

    @staticmethod
    def _format_event(level: str, category: str, symbol: str, message: str,
                      stamp: str) -> str:
        color = theme.LEVEL_COLORS.get(level, theme.TEXT)
        tag = category + (f"/{symbol}" if symbol else "")
        return (
            f'<span style="color:{theme.TEXT_MUTED}">{stamp}</span> '
            f'<span style="color:{color}">[{level}]</span> '
            f'<span style="color:{theme.ACCENT}">{tag}</span> '
            f'<span style="color:{color}">{_escape(message)}</span>'
        )

    def _on_log(self, level: str, category: str, symbol: str, message: str) -> None:
        html = self._format_event(
            level, category, symbol, message, datetime.now().strftime("%H:%M:%S")
        )
        selected = self.level_filter.currentText()
        if selected == "Tous" or selected == level:
            self.log_view.appendHtml(html)
        if category in self.ACTIVITY_CATEGORIES or level == "ERROR":
            self.activity_view.appendHtml(html)

    # ============================================================ journal ====
    ACTIVITY_CATEGORIES = ("ordre", "position", "risque", "connexion")

    def _load_history(self) -> None:
        self._reload_logs()
        for event in self.journal.recent_events(400):
            if event["category"] in self.ACTIVITY_CATEGORIES or event["level"] == "ERROR":
                self.activity_view.appendHtml(self._format_event(
                    event["level"], event["category"], event["symbol"],
                    event["message"], event["ts"][11:19],
                ))

    def _reload_logs(self) -> None:
        self.log_view.clear()
        selected = self.level_filter.currentText()
        for event in self.journal.recent_events(LOG_LIMIT):
            level = event["level"]
            if selected != "Tous" and level != selected:
                continue
            self.log_view.appendHtml(self._format_event(
                level, event["category"], event["symbol"], event["message"],
                event["ts"][11:19],
            ))

    def _refresh_journal_views(self) -> None:
        self._refresh_stats_table()
        self._refresh_trades_table()
        self._refresh_equity_chart()

    def _refresh_stats_table(self) -> None:
        stats = self.journal.statistics()
        pf = stats["profit_factor"]
        rows = [
            ("Trades clotures", f"{int(stats['trades'])}", None),
            ("Taux de reussite", f"{stats['win_rate']:.1f} %",
             theme.GREEN if stats["win_rate"] >= 50 else theme.AMBER),
            ("Gains / pertes", f"{int(stats['wins'])} / {int(stats['losses'])}", None),
            ("Facteur de profit", "∞" if pf == float("inf") else f"{pf:.2f}",
             theme.GREEN if pf >= 1.3 else (theme.AMBER if pf >= 1 else theme.RED)),
            ("Resultat net", signed_money(stats["net"]), pnl_color(stats["net"])),
            ("Esperance / trade", signed_money(stats["expectancy"]),
             pnl_color(stats["expectancy"])),
            ("Gain moyen", money(stats["avg_win"]), theme.GREEN),
            ("Perte moyenne", money(stats["avg_loss"]), theme.RED),
            ("Drawdown (trades)", money(stats["max_drawdown"]), None),
        ]
        self.stats_table.setRowCount(len(rows))
        for row, (label, value, color) in enumerate(rows):
            left = QTableWidgetItem(label)
            left.setForeground(QColor(theme.TEXT_MUTED))
            right = QTableWidgetItem(value)
            right.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
            if color:
                right.setForeground(QColor(color))
            self.stats_table.setItem(row, 0, left)
            self.stats_table.setItem(row, 1, right)

    def _refresh_trades_table(self) -> None:
        trades = self.journal.recent_trades(200)
        self.trades_table.setRowCount(len(trades))
        for row, trade in enumerate(trades):
            profit = trade.get("profit")
            still_open = trade.get("closed_at") is None
            cells = [
                (trade["opened_at"] or "")[:16].replace("T", " "),
                trade["symbol"], trade["side"], f"{trade['volume']:g}",
                f"{trade['price_open']:g}",
                f"{trade['price_close']:g}" if trade.get("price_close") else "—",
                "en cours" if still_open else signed_money(profit or 0.0),
                trade.get("close_reason") or (trade.get("reason") or "")[:60],
            ]
            for column, text in enumerate(cells):
                item = QTableWidgetItem(str(text))
                if column >= 3:
                    item.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
                if column == 2:
                    item.setForeground(QColor(theme.GREEN if trade["side"] == "BUY" else theme.RED))
                if column == 6 and not still_open:
                    item.setForeground(QColor(pnl_color(profit or 0.0)))
                item.setToolTip(trade.get("reason") or "")
                self.trades_table.setItem(row, column, item)

    def _refresh_equity_chart(self) -> None:
        points = self.journal.equity_curve(1500)
        if len(points) < 2:
            self.equity_chart.set_series([], [])
            return
        values = [p["equity"] for p in points]
        labels = [p["ts"][11:16] for p in points]
        self.equity_chart.set_series(values, labels, baseline=points[0]["balance"])

    # =========================================================== fermeture ===
    def closeEvent(self, event) -> None:  # noqa: N802 (API Qt)
        if self.bridge.running:
            answer = QMessageBox.question(
                self, "Quitter",
                "Le moteur tourne encore. Le quitter maintenant laissera les "
                "positions ouvertes sans gestion (ni point mort, ni stop suiveur).\n\n"
                "Quitter quand meme ?",
                QMessageBox.Yes | QMessageBox.Cancel, QMessageBox.Cancel,
            )
            if answer != QMessageBox.Yes:
                event.ignore()
                return
        self._timer.stop()
        self.bridge.stop()
        self.backtest_panel.shutdown()
        self.config.save()
        self.journal.close()
        event.accept()


def _escape(text: str) -> str:
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))

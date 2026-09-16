"""Onglet Parametres : connexion, strategie, risque, execution."""

from __future__ import annotations

from typing import Callable, Dict, Optional

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QCheckBox, QComboBox, QDoubleSpinBox, QFileDialog, QFormLayout, QGridLayout,
    QGroupBox, QHBoxLayout, QInputDialog, QLabel, QLineEdit, QMessageBox,
    QPushButton, QScrollArea, QSpinBox, QVBoxLayout, QWidget,
)

from ..config import AppConfig
from ..core.broker import TIMEFRAMES
from ..core.strategies import STRATEGIES
from . import theme
from .widgets import section_title

CONFIRM_WORD = "JE CONFIRME"


def _spin(minimum, maximum, value, step=1, suffix="") -> QSpinBox:
    box = QSpinBox()
    box.setRange(int(minimum), int(maximum))
    box.setSingleStep(int(step))
    box.setValue(int(value))
    if suffix:
        box.setSuffix(suffix)
    return box


def _dspin(minimum, maximum, value, step=0.1, decimals=2, suffix="") -> QDoubleSpinBox:
    box = QDoubleSpinBox()
    box.setDecimals(decimals)
    box.setRange(float(minimum), float(maximum))
    box.setSingleStep(float(step))
    box.setValue(float(value))
    if suffix:
        box.setSuffix(suffix)
    return box


class SettingsPanel(QWidget):
    """Formulaire de configuration. Emet `applied` quand l'utilisateur valide."""

    applied = Signal()

    def __init__(self, config: AppConfig, parent: Optional[QWidget] = None):
        super().__init__(parent)
        self.config = config
        self._engine_running: Callable[[], bool] = lambda: False
        self._build()
        self.load_from_config()

    def set_running_probe(self, probe: Callable[[], bool]) -> None:
        """Permet au panneau de savoir si le moteur tourne (champs verrouilles)."""
        self._engine_running = probe

    # ------------------------------------------------------------ montage ---
    def _build(self) -> None:
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.NoFrame)
        content = QWidget()
        layout = QVBoxLayout(content)
        layout.setContentsMargins(4, 4, 12, 12)
        layout.setSpacing(14)

        layout.addWidget(section_title(
            "Parametres",
            "Les modifications prennent effet au prochain demarrage du moteur. "
            "Certains champs sont verrouilles pendant que le bot tourne.",
        ))

        layout.addWidget(self._connection_group())
        layout.addWidget(self._strategy_group())
        layout.addWidget(self._risk_group())
        layout.addWidget(self._execution_group())
        layout.addStretch(1)

        scroll.setWidget(content)
        outer.addWidget(scroll)

        bar = QHBoxLayout()
        bar.addStretch(1)
        self.reset_button = QPushButton("Valeurs par defaut")
        self.reset_button.setProperty("kind", "ghost")
        self.reset_button.clicked.connect(self._reset_defaults)
        self.apply_button = QPushButton("Enregistrer")
        self.apply_button.setProperty("kind", "primary")
        self.apply_button.clicked.connect(self._apply)
        bar.addWidget(self.reset_button)
        bar.addWidget(self.apply_button)
        outer.addLayout(bar)

    # ---------------------------------------------------------- connexion ---
    def _connection_group(self) -> QGroupBox:
        box = QGroupBox("Connexion MetaTrader 5")
        form = QFormLayout(box)
        form.setLabelAlignment(Qt.AlignRight)
        form.setSpacing(9)

        path_row = QHBoxLayout()
        self.terminal_path = QLineEdit()
        self.terminal_path.setPlaceholderText(
            r"Laisser vide pour la detection automatique, ex. C:\Program Files\MetaTrader 5\terminal64.exe"
        )
        browse = QPushButton("Parcourir")
        browse.clicked.connect(self._browse_terminal)
        path_row.addWidget(self.terminal_path, 1)
        path_row.addWidget(browse)
        form.addRow("Terminal", path_row)

        self.login = QLineEdit()
        self.login.setPlaceholderText("Vide = utiliser le compte deja ouvert dans le terminal")
        form.addRow("Numero de compte", self.login)

        self.server = QLineEdit()
        self.server.setPlaceholderText("ex. ICMarketsSC-Demo")
        form.addRow("Serveur", self.server)

        self.password = QLineEdit()
        self.password.setEchoMode(QLineEdit.Password)
        form.addRow("Mot de passe", self.password)

        self.remember_password = QCheckBox(
            "Memoriser le mot de passe (stocke en clair dans le fichier de configuration)"
        )
        form.addRow("", self.remember_password)

        self.account_kind = QComboBox()
        self.account_kind.addItem("Compte DEMO", "demo")
        self.account_kind.addItem("Compte REEL", "real")
        self.account_kind.currentIndexChanged.connect(self._account_kind_changed)
        form.addRow("Type de compte", self.account_kind)

        self.account_warning = QLabel()
        self.account_warning.setWordWrap(True)
        form.addRow("", self.account_warning)

        self.offline_simulation = QCheckBox(
            "Mode simulation hors-ligne (marche fictif, aucun terminal requis)"
        )
        self.offline_simulation.setToolTip(
            "Permet de tester l'application sans MetaTrader 5. Les prix sont generes, "
            "les resultats n'ont aucune valeur predictive."
        )
        form.addRow("", self.offline_simulation)
        return box

    def _browse_terminal(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "Selectionner terminal64.exe", "", "Executable (*.exe);;Tous les fichiers (*)"
        )
        if path:
            self.terminal_path.setText(path)

    def _account_kind_changed(self) -> None:
        if self.account_kind.currentData() == "real":
            self.account_warning.setText(
                "Compte REEL selectionne : les ordres engagent de l'argent reel. "
                "Le moteur verifie a la connexion que le terminal est bien sur un "
                "compte reel et refuse de demarrer en cas d'incoherence."
            )
            self.account_warning.setStyleSheet(f"color: {theme.AMBER};")
        else:
            self.account_warning.setText(
                "Compte DEMO : si le terminal est en fait connecte a un compte reel, "
                "le moteur refusera de demarrer."
            )
            self.account_warning.setStyleSheet(f"color: {theme.TEXT_MUTED};")

    # ---------------------------------------------------------- strategie ---
    def _strategy_group(self) -> QGroupBox:
        box = QGroupBox("Strategie")
        grid = QGridLayout(box)
        grid.setSpacing(9)

        self.strategy_name = QComboBox()
        for key, cls in STRATEGIES.items():
            self.strategy_name.addItem(cls.label, key)
        self.strategy_name.currentIndexChanged.connect(self._strategy_changed)

        self.strategy_hint = QLabel()
        self.strategy_hint.setWordWrap(True)
        self.strategy_hint.setProperty("role", "muted")

        self.timeframe = QComboBox()
        self.timeframe.addItems(list(TIMEFRAMES))
        self.higher_timeframe = QComboBox()
        self.higher_timeframe.addItems(list(TIMEFRAMES))

        self.ema_fast = _spin(2, 400, 21)
        self.ema_slow = _spin(3, 500, 50)
        self.ema_trend = _spin(10, 1000, 200)
        self.rsi_period = _spin(2, 100, 14)
        self.atr_period = _spin(2, 100, 14)
        self.adx_period = _spin(2, 100, 14)
        self.adx_trend_min = _dspin(5, 60, 22, 1, 1)
        self.adx_range_max = _dspin(1, 40, 18, 1, 1)
        self.sl_atr_mult = _dspin(0.2, 10, 1.8, 0.1, 2, " x ATR")
        self.tp_atr_mult = _dspin(0.2, 20, 2.7, 0.1, 2, " x ATR")
        self.min_rr = _dspin(0.1, 10, 1.2, 0.1, 2)
        self.mr_min_rr = _dspin(0.1, 10, 0.9, 0.1, 2)
        self.cooldown_bars = _spin(0, 200, 3, 1, " bougies")
        self.require_htf_alignment = QCheckBox("Exiger l'accord de l'unite de temps superieure")

        rows = [
            ("Logique", self.strategy_name),
            ("", self.strategy_hint),
            ("Unite de travail", self.timeframe),
            ("Unite de tendance", self.higher_timeframe),
            ("EMA rapide", self.ema_fast),
            ("EMA moyenne", self.ema_slow),
            ("EMA de fond", self.ema_trend),
            ("Periode RSI", self.rsi_period),
            ("Periode ATR", self.atr_period),
            ("Periode ADX", self.adx_period),
            ("ADX mini (tendance)", self.adx_trend_min),
            ("ADX maxi (range)", self.adx_range_max),
            ("Stop-loss", self.sl_atr_mult),
            ("Take-profit", self.tp_atr_mult),
            ("R:R minimal (tendance)", self.min_rr),
            ("R:R minimal (range)", self.mr_min_rr),
            ("Temporisation", self.cooldown_bars),
            ("", self.require_htf_alignment),
        ]
        for index, (label, widget) in enumerate(rows):
            row, col = divmod(index, 2)
            cell = QWidget()
            cell_layout = QFormLayout(cell)
            cell_layout.setContentsMargins(0, 0, 14, 0)
            cell_layout.setLabelAlignment(Qt.AlignRight)
            cell_layout.addRow(label, widget)
            grid.addWidget(cell, row, col)
        return box

    def _strategy_changed(self) -> None:
        key = self.strategy_name.currentData()
        cls = STRATEGIES.get(key)
        self.strategy_hint.setText(cls.description if cls else "")

    # ------------------------------------------------------------- risque ---
    def _risk_group(self) -> QGroupBox:
        box = QGroupBox("Gestion du risque")
        grid = QGridLayout(box)
        grid.setSpacing(9)

        self.risk_per_trade = _dspin(0.01, 10, 0.5, 0.05, 2, " %")
        self.risk_per_trade.setToolTip(
            "Part de l'equity perdue si le stop est touche. Au-dela de 1 %, "
            "une serie de pertes devient tres couteuse."
        )
        self.max_daily_loss = _dspin(0.1, 50, 2.0, 0.1, 2, " %")
        self.max_drawdown = _dspin(0.5, 90, 10.0, 0.5, 2, " %")
        self.max_open_positions = _spin(1, 50, 3)
        self.max_positions_per_symbol = _spin(1, 20, 1)
        self.max_trades_per_day = _spin(1, 500, 10)
        self.max_spread_points = _spin(1, 2000, 25, 1, " pts")
        self.min_free_margin = _dspin(0, 95, 30.0, 1, 1, " %")
        self.max_lot = _dspin(0.01, 500, 1.0, 0.01, 2, " lots")
        self.breakeven_at_r = _dspin(0, 10, 1.0, 0.1, 2, " R")
        self.trailing_start_r = _dspin(0, 20, 1.5, 0.1, 2, " R")
        self.trailing_atr_mult = _dspin(0.1, 10, 1.5, 0.1, 2, " x ATR")
        self.session_start = _spin(0, 23, 7, 1, " h")
        self.session_end = _spin(0, 23, 20, 1, " h")
        self.friday_cutoff = _spin(0, 23, 18, 1, " h")
        self.close_all_on_daily_stop = QCheckBox("Fermer les positions quand un coupe-circuit se declenche")

        rows = [
            ("Risque par trade", self.risk_per_trade),
            ("Perte max / jour", self.max_daily_loss),
            ("Drawdown max", self.max_drawdown),
            ("Positions simultanees", self.max_open_positions),
            ("Positions / symbole", self.max_positions_per_symbol),
            ("Trades max / jour", self.max_trades_per_day),
            ("Spread maxi", self.max_spread_points),
            ("Marge libre mini", self.min_free_margin),
            ("Volume plafond", self.max_lot),
            ("Point mort a", self.breakeven_at_r),
            ("Stop suiveur des", self.trailing_start_r),
            ("Distance du suiveur", self.trailing_atr_mult),
            ("Debut de session", self.session_start),
            ("Fin de session", self.session_end),
            ("Coupure vendredi", self.friday_cutoff),
            ("", self.close_all_on_daily_stop),
        ]
        for index, (label, widget) in enumerate(rows):
            row, col = divmod(index, 3)
            cell = QWidget()
            cell_layout = QFormLayout(cell)
            cell_layout.setContentsMargins(0, 0, 14, 0)
            cell_layout.setLabelAlignment(Qt.AlignRight)
            cell_layout.addRow(label, widget)
            grid.addWidget(cell, row, col)

        days = QWidget()
        days_layout = QHBoxLayout(days)
        days_layout.setContentsMargins(0, 6, 0, 0)
        days_layout.addWidget(QLabel("Jours actifs :"))
        self.day_boxes: Dict[str, QCheckBox] = {}
        for field, label in (
            ("trade_monday", "Lundi"), ("trade_tuesday", "Mardi"),
            ("trade_wednesday", "Mercredi"), ("trade_thursday", "Jeudi"),
            ("trade_friday", "Vendredi"),
        ):
            cb = QCheckBox(label)
            self.day_boxes[field] = cb
            days_layout.addWidget(cb)
        days_layout.addStretch(1)
        grid.addWidget(days, (len(rows) + 2) // 3, 0, 1, 3)
        return box

    # ---------------------------------------------------------- execution ---
    def _execution_group(self) -> QGroupBox:
        box = QGroupBox("Execution")
        form = QFormLayout(box)
        form.setLabelAlignment(Qt.AlignRight)
        form.setSpacing(9)

        self.symbols = QLineEdit()
        self.symbols.setPlaceholderText("EURUSD, GBPUSD, USDJPY")
        self.symbols.setToolTip(
            "Noms exactement tels qu'ils apparaissent dans le Market Watch du terminal "
            "(certains brokers ajoutent un suffixe : EURUSD.a, EURUSDm...)."
        )
        form.addRow("Symboles", self.symbols)

        self.magic = _spin(1, 2_000_000_000, 730144)
        self.magic.setToolTip(
            "Identifiant des ordres du bot. Il ne touchera jamais une position "
            "portant un autre magic number."
        )
        form.addRow("Magic number", self.magic)

        self.deviation = _spin(0, 500, 20, 1, " pts")
        form.addRow("Slippage tolere", self.deviation)

        self.poll_seconds = _dspin(0.5, 60, 2.0, 0.5, 1, " s")
        form.addRow("Periode de cycle", self.poll_seconds)

        self.live_orders = QCheckBox("Autoriser l'envoi d'ordres au broker")
        self.live_orders.setToolTip(
            "Decoche : le bot analyse et journalise sans rien envoyer (mode analyse)."
        )
        self.live_orders.clicked.connect(self._live_orders_clicked)
        form.addRow("", self.live_orders)

        self.live_hint = QLabel()
        self.live_hint.setWordWrap(True)
        form.addRow("", self.live_hint)
        self._update_live_hint()
        return box

    def _live_orders_clicked(self, checked: bool) -> None:
        """Confirmation explicite avant d'armer l'envoi d'ordres reels."""
        if not checked:
            self._update_live_hint()
            return
        if self.offline_simulation.isChecked():
            self._update_live_hint()
            return
        if self.account_kind.currentData() != "real":
            self._update_live_hint()
            return
        text, ok = QInputDialog.getText(
            self,
            "Confirmation - compte reel",
            "Vous allez autoriser l'envoi d'ordres sur un compte REEL.\n\n"
            f"Tapez  {CONFIRM_WORD}  pour valider :",
        )
        if not ok or text.strip().upper() != CONFIRM_WORD:
            self.live_orders.setChecked(False)
            QMessageBox.information(
                self, "Annule", "L'envoi d'ordres reels n'a pas ete active."
            )
        self._update_live_hint()

    def _update_live_hint(self) -> None:
        if not self.live_orders.isChecked():
            self.live_hint.setText(
                "Mode analyse : les signaux sont calcules et journalises, "
                "aucun ordre n'est transmis. C'est la position par defaut."
            )
            self.live_hint.setStyleSheet(f"color: {theme.TEXT_MUTED};")
        elif self.offline_simulation.isChecked():
            self.live_hint.setText(
                "Ordres actifs sur le marche simule : aucun argent reel n'est engage."
            )
            self.live_hint.setStyleSheet(f"color: {theme.ACCENT};")
        elif self.account_kind.currentData() == "real":
            self.live_hint.setText("ORDRES REELS ARMES : de l'argent reel sera engage.")
            self.live_hint.setStyleSheet(f"color: {theme.RED}; font-weight: 600;")
        else:
            self.live_hint.setText("Ordres actifs sur compte demo : aucun argent reel engage.")
            self.live_hint.setStyleSheet(f"color: {theme.GREEN};")

    # ------------------------------------------------------ chargement ------
    def load_from_config(self) -> None:
        c = self.config
        self.terminal_path.setText(c.connection.terminal_path)
        self.login.setText(str(c.connection.login) if c.connection.login else "")
        self.server.setText(c.connection.server)
        self.password.setText(c.connection.password)
        self.remember_password.setChecked(c.connection.remember_password)
        self.account_kind.setCurrentIndex(1 if c.connection.account_kind == "real" else 0)
        self.offline_simulation.setChecked(c.connection.offline_simulation)
        self._account_kind_changed()

        s = c.strategy
        index = self.strategy_name.findData(s.name)
        self.strategy_name.setCurrentIndex(max(0, index))
        self._strategy_changed()
        self.timeframe.setCurrentText(s.timeframe)
        self.higher_timeframe.setCurrentText(s.higher_timeframe)
        self.ema_fast.setValue(s.ema_fast)
        self.ema_slow.setValue(s.ema_slow)
        self.ema_trend.setValue(s.ema_trend)
        self.rsi_period.setValue(s.rsi_period)
        self.atr_period.setValue(s.atr_period)
        self.adx_period.setValue(s.adx_period)
        self.adx_trend_min.setValue(s.adx_trend_min)
        self.adx_range_max.setValue(s.adx_range_max)
        self.sl_atr_mult.setValue(s.sl_atr_mult)
        self.tp_atr_mult.setValue(s.tp_atr_mult)
        self.min_rr.setValue(s.min_rr)
        self.mr_min_rr.setValue(s.mr_min_rr)
        self.cooldown_bars.setValue(s.cooldown_bars)
        self.require_htf_alignment.setChecked(s.require_htf_alignment)

        r = c.risk
        self.risk_per_trade.setValue(r.risk_per_trade_pct)
        self.max_daily_loss.setValue(r.max_daily_loss_pct)
        self.max_drawdown.setValue(r.max_drawdown_pct)
        self.max_open_positions.setValue(r.max_open_positions)
        self.max_positions_per_symbol.setValue(r.max_positions_per_symbol)
        self.max_trades_per_day.setValue(r.max_trades_per_day)
        self.max_spread_points.setValue(r.max_spread_points)
        self.min_free_margin.setValue(r.min_free_margin_pct)
        self.max_lot.setValue(r.max_lot)
        self.breakeven_at_r.setValue(r.breakeven_at_r)
        self.trailing_start_r.setValue(r.trailing_start_r)
        self.trailing_atr_mult.setValue(r.trailing_atr_mult)
        self.session_start.setValue(r.session_start_hour)
        self.session_end.setValue(r.session_end_hour)
        self.friday_cutoff.setValue(r.friday_cutoff_hour)
        self.close_all_on_daily_stop.setChecked(r.close_all_on_daily_stop)
        for field, box in self.day_boxes.items():
            box.setChecked(getattr(r, field, True))

        t = c.trading
        self.symbols.setText(", ".join(t.symbols))
        self.magic.setValue(t.magic)
        self.deviation.setValue(t.deviation_points)
        self.poll_seconds.setValue(t.poll_seconds)
        self.live_orders.setChecked(t.live_orders_enabled)
        self._update_live_hint()

    # ------------------------------------------------------ enregistrement --
    def _collect_symbols(self) -> list[str]:
        raw = self.symbols.text().replace(";", ",").replace(" ", ",")
        return [s.strip().upper() for s in raw.split(",") if s.strip()]

    def _validate(self) -> Optional[str]:
        if not self._collect_symbols():
            return "Indiquez au moins un symbole a trader."
        if self.login.text().strip() and not self.login.text().strip().isdigit():
            return "Le numero de compte doit etre un nombre entier."
        if self.ema_fast.value() >= self.ema_slow.value():
            return "L'EMA rapide doit avoir une periode plus courte que l'EMA moyenne."
        if self.ema_slow.value() >= self.ema_trend.value():
            return "L'EMA moyenne doit avoir une periode plus courte que l'EMA de fond."
        if self.adx_range_max.value() >= self.adx_trend_min.value():
            return ("Le seuil ADX de range doit rester sous le seuil de tendance, "
                    "sinon les deux regimes se chevauchent.")
        if self.tp_atr_mult.value() <= self.sl_atr_mult.value() * self.min_rr.value():
            return (f"Avec un stop de {self.sl_atr_mult.value()} x ATR et un R:R minimal de "
                    f"{self.min_rr.value()}, le take-profit doit depasser "
                    f"{self.sl_atr_mult.value() * self.min_rr.value():.2f} x ATR, "
                    "sinon aucun signal de tendance ne passera le filtre.")
        if self.risk_per_trade.value() * self.max_open_positions.value() > \
                self.max_daily_loss.value():
            return (f"Incoherence : {self.max_open_positions.value()} positions a "
                    f"{self.risk_per_trade.value()} % risquent "
                    f"{self.risk_per_trade.value() * self.max_open_positions.value():.2f} %, "
                    f"au-dela de la perte journaliere maximale "
                    f"({self.max_daily_loss.value()} %).")
        return None

    def _apply(self) -> None:
        problem = self._validate()
        if problem:
            QMessageBox.warning(self, "Parametres invalides", problem)
            return

        c = self.config
        c.connection.terminal_path = self.terminal_path.text().strip()
        c.connection.login = int(self.login.text().strip() or 0)
        c.connection.server = self.server.text().strip()
        c.connection.remember_password = self.remember_password.isChecked()
        c.connection.password = self.password.text() if self.remember_password.isChecked() else ""
        c.connection.account_kind = self.account_kind.currentData()
        c.connection.offline_simulation = self.offline_simulation.isChecked()

        s = c.strategy
        s.name = self.strategy_name.currentData()
        s.timeframe = self.timeframe.currentText()
        s.higher_timeframe = self.higher_timeframe.currentText()
        s.ema_fast = self.ema_fast.value()
        s.ema_slow = self.ema_slow.value()
        s.ema_trend = self.ema_trend.value()
        s.rsi_period = self.rsi_period.value()
        s.atr_period = self.atr_period.value()
        s.adx_period = self.adx_period.value()
        s.adx_trend_min = self.adx_trend_min.value()
        s.adx_range_max = self.adx_range_max.value()
        s.sl_atr_mult = self.sl_atr_mult.value()
        s.tp_atr_mult = self.tp_atr_mult.value()
        s.min_rr = self.min_rr.value()
        s.mr_min_rr = self.mr_min_rr.value()
        s.cooldown_bars = self.cooldown_bars.value()
        s.require_htf_alignment = self.require_htf_alignment.isChecked()

        r = c.risk
        r.risk_per_trade_pct = self.risk_per_trade.value()
        r.max_daily_loss_pct = self.max_daily_loss.value()
        r.max_drawdown_pct = self.max_drawdown.value()
        r.max_open_positions = self.max_open_positions.value()
        r.max_positions_per_symbol = self.max_positions_per_symbol.value()
        r.max_trades_per_day = self.max_trades_per_day.value()
        r.max_spread_points = self.max_spread_points.value()
        r.min_free_margin_pct = self.min_free_margin.value()
        r.max_lot = self.max_lot.value()
        r.breakeven_at_r = self.breakeven_at_r.value()
        r.trailing_start_r = self.trailing_start_r.value()
        r.trailing_atr_mult = self.trailing_atr_mult.value()
        r.session_start_hour = self.session_start.value()
        r.session_end_hour = self.session_end.value()
        r.friday_cutoff_hour = self.friday_cutoff.value()
        r.close_all_on_daily_stop = self.close_all_on_daily_stop.isChecked()
        for field, box in self.day_boxes.items():
            setattr(r, field, box.isChecked())

        t = c.trading
        t.symbols = self._collect_symbols()
        t.magic = self.magic.value()
        t.deviation_points = self.deviation.value()
        t.poll_seconds = self.poll_seconds.value()
        t.live_orders_enabled = self.live_orders.isChecked()

        c.save()
        self._update_live_hint()
        self.applied.emit()

        if self._engine_running():
            QMessageBox.information(
                self, "Enregistre",
                "Parametres enregistres. Le moteur tourne : redemarrez-le pour "
                "que la strategie, les symboles et la connexion soient repris.",
            )
        else:
            QMessageBox.information(self, "Enregistre", "Parametres enregistres.")

    def _reset_defaults(self) -> None:
        answer = QMessageBox.question(
            self, "Valeurs par defaut",
            "Remettre tous les parametres a leurs valeurs par defaut ?\n"
            "Les identifiants de connexion sont conserves.",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if answer != QMessageBox.Yes:
            return
        from ..config import RiskConfig, StrategyConfig, TradingConfig
        self.config.risk = RiskConfig()
        self.config.strategy = StrategyConfig()
        self.config.trading = TradingConfig()
        self.load_from_config()

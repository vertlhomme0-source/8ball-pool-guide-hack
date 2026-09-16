"""Composants d'interface reutilisables."""

from __future__ import annotations

from datetime import datetime
from typing import List, Optional, Sequence, Tuple

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import (
    QColor, QFont, QFontMetrics, QLinearGradient, QPainter, QPainterPath, QPen,
)
from PySide6.QtWidgets import (
    QFrame, QHBoxLayout, QLabel, QSizePolicy, QVBoxLayout, QWidget,
)

from . import theme


class Card(QFrame):
    """Panneau arrondi, brique de base de toutes les vues."""

    def __init__(self, parent: Optional[QWidget] = None, margins: int = 16, spacing: int = 10):
        super().__init__(parent)
        self.setObjectName("Card")
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(margins, margins, margins, margins)
        self._layout.setSpacing(spacing)

    def body(self) -> QVBoxLayout:
        return self._layout

    def add(self, widget: QWidget) -> QWidget:
        self._layout.addWidget(widget)
        return widget


class StatCard(Card):
    """Libelle + grande valeur + note secondaire."""

    def __init__(self, caption: str, value: str = "-", hint: str = "",
                 parent: Optional[QWidget] = None):
        super().__init__(parent, margins=14, spacing=4)
        self.caption_label = QLabel(caption)
        self.caption_label.setProperty("role", "caption")
        self.value_label = QLabel(value)
        self.value_label.setProperty("role", "value")
        self.hint_label = QLabel(hint)
        self.hint_label.setProperty("role", "muted")
        self.hint_label.setWordWrap(True)
        for w in (self.caption_label, self.value_label, self.hint_label):
            self._layout.addWidget(w)
        self._layout.addStretch(1)
        self.setMinimumWidth(150)
        # Deux lignes de texte secondaire tiennent sans etre rognees.
        self.setMinimumHeight(112)

    def set_value(self, text: str, color: Optional[str] = None) -> None:
        self.value_label.setText(text)
        self.value_label.setStyleSheet(f"color: {color};" if color else "")

    def set_hint(self, text: str) -> None:
        self.hint_label.setText(text)


class Badge(QLabel):
    """Pastille d'etat coloree."""

    def __init__(self, text: str = "", color: str = theme.TEXT_MUTED,
                 parent: Optional[QWidget] = None):
        super().__init__(text, parent)
        self.setProperty("role", "badge")
        self.set_color(color)

    def set_color(self, color: str) -> None:
        self._color = color
        self.setStyleSheet(
            f"color: {color}; background: {theme.PANEL_HI};"
            f" border: 1px solid {color}; padding: 3px 10px; border-radius: 9px;"
            f" font-size: 11px; font-weight: 600;"
        )

    def set_state(self, text: str, color: str) -> None:
        self.setText(text)
        self.set_color(color)


class SparklineChart(QWidget):
    """Courbe d'equity dessinee a la main.

    Pas de dependance graphique supplementaire : moins de paquets a installer,
    donc moins de choses qui cassent au deploiement.
    """

    def __init__(self, parent: Optional[QWidget] = None):
        super().__init__(parent)
        self._values: List[float] = []
        self._labels: List[str] = []
        self._baseline: Optional[float] = None
        self.setMinimumHeight(180)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)

    def set_series(self, values: Sequence[float], labels: Optional[Sequence[str]] = None,
                   baseline: Optional[float] = None) -> None:
        self._values = [float(v) for v in values]
        self._labels = list(labels or [])
        self._baseline = baseline
        self.update()

    def paintEvent(self, event) -> None:  # noqa: N802 (API Qt)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        rect = QRectF(self.rect())
        painter.fillRect(rect, QColor(theme.PANEL))

        if len(self._values) < 2:
            painter.setPen(QColor(theme.TEXT_MUTED))
            painter.drawText(rect, Qt.AlignCenter, "Pas encore de donnees")
            painter.end()
            return

        pad_left, pad_right, pad_top, pad_bottom = 62.0, 14.0, 14.0, 24.0
        plot = QRectF(
            rect.left() + pad_left, rect.top() + pad_top,
            max(1.0, rect.width() - pad_left - pad_right),
            max(1.0, rect.height() - pad_top - pad_bottom),
        )

        lo, hi = min(self._values), max(self._values)
        if self._baseline is not None:
            lo, hi = min(lo, self._baseline), max(hi, self._baseline)
        if hi - lo < 1e-9:
            hi, lo = hi + 1.0, lo - 1.0
        span = hi - lo
        lo -= span * 0.08
        hi += span * 0.08
        span = hi - lo

        def to_point(i: int, value: float) -> QPointF:
            x = plot.left() + plot.width() * (i / max(1, len(self._values) - 1))
            y = plot.bottom() - plot.height() * ((value - lo) / span)
            return QPointF(x, y)

        # Grille + graduations
        small = QFont(self.font())
        small.setPointSizeF(max(7.0, small.pointSizeF() - 2))
        painter.setFont(small)
        grid_pen = QPen(QColor(theme.BORDER))
        grid_pen.setWidthF(1.0)
        for i in range(5):
            value = hi - span * i / 4.0
            y = plot.top() + plot.height() * i / 4.0
            painter.setPen(grid_pen)
            painter.drawLine(QPointF(plot.left(), y), QPointF(plot.right(), y))
            painter.setPen(QColor(theme.TEXT_MUTED))
            painter.drawText(
                QRectF(rect.left(), y - 8, pad_left - 8, 16),
                Qt.AlignRight | Qt.AlignVCenter,
                f"{value:,.0f}".replace(",", " "),
            )

        # Ligne de reference (capital de depart)
        if self._baseline is not None and lo <= self._baseline <= hi:
            y = plot.bottom() - plot.height() * ((self._baseline - lo) / span)
            ref = QPen(QColor(theme.TEXT_MUTED))
            ref.setStyle(Qt.DashLine)
            painter.setPen(ref)
            painter.drawLine(QPointF(plot.left(), y), QPointF(plot.right(), y))

        up = self._values[-1] >= (self._baseline if self._baseline is not None else self._values[0])
        color = QColor(theme.GREEN if up else theme.RED)

        points = [to_point(i, v) for i, v in enumerate(self._values)]

        # Aplat degrade sous la courbe
        area = QPainterPath()
        area.moveTo(points[0].x(), plot.bottom())
        for p in points:
            area.lineTo(p)
        area.lineTo(points[-1].x(), plot.bottom())
        area.closeSubpath()
        gradient = QLinearGradient(0, plot.top(), 0, plot.bottom())
        fill = QColor(color)
        fill.setAlpha(80)
        gradient.setColorAt(0.0, fill)
        transparent = QColor(color)
        transparent.setAlpha(0)
        gradient.setColorAt(1.0, transparent)
        painter.fillPath(area, gradient)

        line = QPainterPath()
        line.moveTo(points[0])
        for p in points[1:]:
            line.lineTo(p)
        pen = QPen(color)
        pen.setWidthF(2.0)
        pen.setJoinStyle(Qt.RoundJoin)
        painter.setPen(pen)
        painter.drawPath(line)

        painter.setBrush(color)
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(points[-1], 3.5, 3.5)

        # Bornes temporelles
        if self._labels:
            painter.setPen(QColor(theme.TEXT_MUTED))
            metrics = QFontMetrics(small)
            painter.drawText(
                QPointF(plot.left(), rect.bottom() - 6), self._labels[0]
            )
            last = self._labels[-1]
            painter.drawText(
                QPointF(plot.right() - metrics.horizontalAdvance(last), rect.bottom() - 6), last
            )
        painter.end()


def section_title(text: str, subtitle: str = "") -> QWidget:
    """Titre de section avec sous-titre optionnel."""
    holder = QWidget()
    layout = QVBoxLayout(holder)
    layout.setContentsMargins(0, 0, 0, 0)
    layout.setSpacing(2)
    title = QLabel(text)
    title.setProperty("role", "h2")
    layout.addWidget(title)
    if subtitle:
        sub = QLabel(subtitle)
        sub.setProperty("role", "muted")
        sub.setWordWrap(True)
        layout.addWidget(sub)
    return holder


def money(value: float, currency: str = "") -> str:
    suffix = f" {currency}" if currency else ""
    return f"{value:,.2f}{suffix}".replace(",", " ")


def signed_money(value: float, currency: str = "") -> str:
    suffix = f" {currency}" if currency else ""
    return f"{value:+,.2f}{suffix}".replace(",", " ")


def pnl_color(value: float) -> str:
    if value > 0:
        return theme.GREEN
    if value < 0:
        return theme.RED
    return theme.TEXT

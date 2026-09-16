"""Theme sombre de l'application (palette + feuille de style Qt)."""

from __future__ import annotations

# Palette centralisee : ne jamais ecrire une couleur en dur ailleurs.
BG          = "#0E1420"
BG_ALT      = "#131B2B"
PANEL       = "#172136"
PANEL_HI    = "#1E2A42"
BORDER      = "#26334D"
TEXT        = "#E6ECF5"
TEXT_MUTED  = "#8695AF"
ACCENT      = "#3B82F6"
ACCENT_HI   = "#60A5FA"
GREEN       = "#22C55E"
RED         = "#EF4444"
AMBER       = "#F59E0B"
PURPLE      = "#A78BFA"

LEVEL_COLORS = {
    "DEBUG": TEXT_MUTED,
    "INFO": TEXT,
    "WARN": AMBER,
    "ERROR": RED,
}

FONT_FAMILY = '"Segoe UI", "Inter", "Roboto", sans-serif'

STYLESHEET = f"""
* {{
    font-family: {FONT_FAMILY};
    font-size: 13px;
    color: {TEXT};
}}
QWidget#Root, QMainWindow {{ background: {BG}; }}

/* Sans cette regle, le viewport d'un QScrollArea garde le fond clair du
   style natif et rend les libelles illisibles. */
QScrollArea {{ background: transparent; border: none; }}
QScrollArea > QWidget > QWidget {{ background: transparent; }}
QAbstractScrollArea {{ background: transparent; }}
QTabWidget > QWidget {{ background: transparent; }}

QLabel[role="h1"]      {{ font-size: 20px; font-weight: 600; }}
QLabel[role="h2"]      {{ font-size: 15px; font-weight: 600; }}
QLabel[role="muted"]   {{ color: {TEXT_MUTED}; }}
QLabel[role="caption"] {{ color: {TEXT_MUTED}; font-size: 11px;
                          letter-spacing: 0.6px; text-transform: uppercase; }}
QLabel[role="value"]   {{ font-size: 22px; font-weight: 600; }}
QLabel[role="badge"]   {{ padding: 3px 10px; border-radius: 9px;
                          background: {PANEL_HI}; font-size: 11px; font-weight: 600; }}

QFrame#Card {{
    background: {PANEL};
    border: 1px solid {BORDER};
    border-radius: 12px;
}}
QFrame#Divider {{ background: {BORDER}; max-height: 1px; border: none; }}

QPushButton {{
    background: {PANEL_HI};
    border: 1px solid {BORDER};
    border-radius: 8px;
    padding: 8px 16px;
    font-weight: 600;
}}
QPushButton:hover    {{ background: {BORDER}; }}
QPushButton:pressed  {{ background: {PANEL}; }}
QPushButton:disabled {{ color: {TEXT_MUTED}; background: {BG_ALT}; }}
QPushButton[kind="primary"] {{ background: {ACCENT}; border-color: {ACCENT}; color: #FFFFFF; }}
QPushButton[kind="primary"]:hover {{ background: {ACCENT_HI}; }}
QPushButton[kind="danger"]  {{ background: {RED}; border-color: {RED}; color: #FFFFFF; }}
QPushButton[kind="danger"]:hover {{ background: #F87171; }}
QPushButton[kind="ghost"]   {{ background: transparent; }}

QLineEdit, QComboBox, QSpinBox, QDoubleSpinBox, QPlainTextEdit, QTextEdit {{
    background: {BG_ALT};
    border: 1px solid {BORDER};
    border-radius: 8px;
    padding: 7px 10px;
    selection-background-color: {ACCENT};
}}
QLineEdit:focus, QComboBox:focus, QSpinBox:focus, QDoubleSpinBox:focus {{
    border-color: {ACCENT};
}}
QComboBox::drop-down {{ border: none; width: 22px; }}
QComboBox QAbstractItemView {{
    background: {PANEL};
    border: 1px solid {BORDER};
    selection-background-color: {ACCENT};
    outline: none;
}}
QSpinBox::up-button, QSpinBox::down-button,
QDoubleSpinBox::up-button, QDoubleSpinBox::down-button {{ width: 16px; }}

QCheckBox::indicator {{
    width: 17px; height: 17px;
    border: 1px solid {BORDER};
    border-radius: 5px;
    background: {BG_ALT};
}}
QCheckBox::indicator:checked {{ background: {ACCENT}; border-color: {ACCENT}; }}
QCheckBox:disabled {{ color: {TEXT_MUTED}; }}

QTabWidget::pane {{ border: none; background: transparent; }}
QTabBar::tab {{
    background: transparent;
    color: {TEXT_MUTED};
    padding: 9px 18px;
    margin-right: 4px;
    border-radius: 8px;
    font-weight: 600;
}}
QTabBar::tab:selected {{ background: {PANEL}; color: {TEXT}; }}
QTabBar::tab:hover:!selected {{ color: {TEXT}; }}

QTableWidget {{
    background: {PANEL};
    alternate-background-color: {BG_ALT};
    border: 1px solid {BORDER};
    border-radius: 10px;
    gridline-color: {BORDER};
    selection-background-color: {PANEL_HI};
    selection-color: {TEXT};
}}
QHeaderView::section {{
    background: {BG_ALT};
    color: {TEXT_MUTED};
    border: none;
    border-bottom: 1px solid {BORDER};
    padding: 8px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
}}
QTableWidget::item {{ padding: 6px; border: none; }}

QScrollBar:vertical {{ background: transparent; width: 10px; margin: 2px; }}
QScrollBar::handle:vertical {{ background: {BORDER}; border-radius: 5px; min-height: 28px; }}
QScrollBar::handle:vertical:hover {{ background: {TEXT_MUTED}; }}
QScrollBar:horizontal {{ background: transparent; height: 10px; margin: 2px; }}
QScrollBar::handle:horizontal {{ background: {BORDER}; border-radius: 5px; min-width: 28px; }}
QScrollBar::add-line, QScrollBar::sub-line {{ height: 0; width: 0; }}
QScrollBar::add-page, QScrollBar::sub-page {{ background: transparent; }}

QGroupBox {{
    border: 1px solid {BORDER};
    border-radius: 10px;
    margin-top: 14px;
    padding-top: 12px;
    font-weight: 600;
}}
QGroupBox::title {{
    subcontrol-origin: margin;
    left: 12px;
    padding: 0 6px;
    color: {TEXT_MUTED};
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.6px;
}}

QProgressBar {{
    background: {BG_ALT};
    border: 1px solid {BORDER};
    border-radius: 7px;
    height: 14px;
    text-align: center;
    font-size: 11px;
}}
QProgressBar::chunk {{ background: {ACCENT}; border-radius: 6px; }}

QToolTip {{
    background: {PANEL_HI};
    border: 1px solid {BORDER};
    border-radius: 6px;
    padding: 6px;
    color: {TEXT};
}}
QSplitter::handle {{ background: {BORDER}; }}
QMenu {{ background: {PANEL}; border: 1px solid {BORDER}; border-radius: 8px; padding: 4px; }}
QMenu::item {{ padding: 6px 22px; border-radius: 6px; }}
QMenu::item:selected {{ background: {ACCENT}; }}
QStatusBar {{ background: {BG_ALT}; border-top: 1px solid {BORDER}; color: {TEXT_MUTED}; }}
"""

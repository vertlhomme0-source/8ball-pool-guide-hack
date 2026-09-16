"""Point d'entree de l'application.

Lancement : `python -m app` depuis le dossier du projet, ou run.bat sous Windows.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Permet de lancer le fichier directement (python app/__main__.py) en plus de
# `python -m app`.
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    __package__ = "app"

from PySide6.QtCore import Qt
from PySide6.QtGui import QFont
from PySide6.QtWidgets import QApplication, QMessageBox

from .config import LOG_DIR, AppConfig
from .core.journal import Journal
from .logging_setup import get_logger, install_exception_hooks, setup_logging
from .ui import theme
from .ui.main_window import MainWindow


def main() -> int:
    setup_logging()
    logger = get_logger()
    logger.info("Demarrage de l'application")

    # Qt 6 gere le HiDPI tout seul ; on ne garde que l'arrondi des facteurs,
    # qui evite les polices floues sur les ecrans 125 % de Windows 10.
    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )

    app = QApplication(sys.argv)
    app.setApplicationName("MT5 Trading Bot")
    app.setOrganizationName("MT5TradingBot")
    app.setStyle("Fusion")
    app.setStyleSheet(theme.STYLESHEET)
    app.setFont(QFont("Segoe UI", 9))

    def show_fatal(summary: str, details: str) -> None:
        box = QMessageBox()
        box.setIcon(QMessageBox.Critical)
        box.setWindowTitle("Erreur inattendue")
        box.setText(
            "Une erreur inattendue s'est produite.\n\n"
            f"{summary}\n\n"
            f"Le detail complet est dans :\n{LOG_DIR / 'app.log'}"
        )
        box.setDetailedText(details)
        box.exec()

    install_exception_hooks(show_fatal)

    config = AppConfig.load()
    journal = Journal()

    window = MainWindow(config, journal)
    window.show()
    logger.info("Interface affichee")
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())

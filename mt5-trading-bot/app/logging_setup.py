"""Journalisation fichier + capture des exceptions non rattrapees.

Objectif : qu'aucun plantage ne se traduise par une fenetre qui disparait sans
explication. Tout ce qui echappe au code est ecrit dans un fichier et montre a
l'utilisateur.
"""

from __future__ import annotations

import logging
import logging.handlers
import sys
import threading
import traceback
from pathlib import Path
from typing import Callable, Optional

from .config import LOG_DIR

_LOGGER_NAME = "mt5bot"


def setup_logging(level: int = logging.INFO) -> logging.Logger:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger(_LOGGER_NAME)
    if logger.handlers:
        return logger
    logger.setLevel(level)

    file_handler = logging.handlers.RotatingFileHandler(
        LOG_DIR / "app.log", maxBytes=2_000_000, backupCount=5, encoding="utf-8"
    )
    file_handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)-7s %(threadName)-14s %(name)s: %(message)s")
    )
    logger.addHandler(file_handler)

    console = logging.StreamHandler(sys.stderr)
    console.setFormatter(logging.Formatter("%(levelname)-7s %(message)s"))
    logger.addHandler(console)
    return logger


def get_logger() -> logging.Logger:
    return logging.getLogger(_LOGGER_NAME)


def install_exception_hooks(on_error: Optional[Callable[[str, str], None]] = None) -> None:
    """Redirige les exceptions non rattrapees, thread principal et threads secondaires."""
    logger = get_logger()

    def handle(exc_type, exc_value, exc_tb) -> None:
        if issubclass(exc_type, KeyboardInterrupt):
            sys.__excepthook__(exc_type, exc_value, exc_tb)
            return
        details = "".join(traceback.format_exception(exc_type, exc_value, exc_tb))
        logger.critical("Exception non rattrapee :\n%s", details)
        if on_error is not None:
            try:
                on_error(f"{exc_type.__name__}: {exc_value}", details)
            except Exception:
                logger.exception("Le gestionnaire d'erreur a lui-meme echoue")

    sys.excepthook = handle

    def thread_hook(args) -> None:
        handle(args.exc_type, args.exc_value, args.exc_traceback)

    threading.excepthook = thread_hook

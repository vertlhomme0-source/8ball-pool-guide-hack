"""Planificateur : envoie le rapport chaque jour à REPORT_TIME, sans dépendance externe.

Si l'application était arrêtée à l'heure prévue, le rapport du jour part dès le
redémarrage (rattrapage). Un rapport automatique n'est jamais envoyé deux fois.
"""

from __future__ import annotations

import logging
import threading
from datetime import datetime

from config import Config
from database import Database
from mailer import MailError, send_daily_report

log = logging.getLogger(__name__)

RETRY_DELAY_SECONDS = 15 * 60


class DailyReportScheduler:
    def __init__(self, cfg: Config, db: Database, check_interval: float = 30):
        self.cfg = cfg
        self.db = db
        self.check_interval = check_interval
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._last_failure: datetime | None = None

    def is_due(self, now: datetime) -> bool:
        hour, minute = self.cfg.report_hour_minute
        if (now.hour, now.minute) < (hour, minute):
            return False
        if self._last_failure and (now - self._last_failure).total_seconds() < RETRY_DELAY_SECONDS:
            return False
        return not self.db.report_sent_automatically(now.date())

    def tick(self, now: datetime | None = None) -> bool:
        """Vérifie et envoie si nécessaire. Retourne True si un rapport est parti."""
        now = now or datetime.now(self.cfg.tz)
        if not self.is_due(now):
            return False
        try:
            send_daily_report(self.cfg, self.db, now.date(), automatic=True)
        except MailError as exc:
            self._last_failure = now
            log.error("Rapport du %s non envoyé : %s (nouvel essai dans 15 min)", now.date(), exc)
            return False
        self._last_failure = None
        log.info("Rapport du %s envoyé à %s", now.date(), ", ".join(self.cfg.report_recipients))
        return True

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                self.tick()
            except Exception:  # le thread ne doit jamais mourir silencieusement
                log.exception("Erreur inattendue dans le planificateur")
            self._stop.wait(self.check_interval)

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._thread = threading.Thread(target=self._run, name="daily-report", daemon=True)
        self._thread.start()
        log.info("Planificateur démarré : rapport quotidien à %s (%s)",
                 self.cfg.report_time, self.cfg.timezone)

    def stop(self) -> None:
        self._stop.set()

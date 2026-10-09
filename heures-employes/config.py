"""Configuration de l'application, lue depuis les variables d'environnement (ou un fichier .env)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from zoneinfo import ZoneInfo

BASE_DIR = Path(__file__).resolve().parent


def load_dotenv(path: Path) -> None:
    """Charge un fichier .env simple (CLE=valeur) sans écraser l'environnement existant."""
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key.strip(), value)


def _bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "oui", "on"}


@dataclass
class Config:
    secret_key: str = "dev-secret-a-changer"
    database_path: str = str(BASE_DIR / "heures.db")
    timezone: str = "America/Toronto"
    company_name: str = "Mon Entreprise"

    report_time: str = "18:00"
    report_recipients: list[str] = field(default_factory=list)
    scheduler_enabled: bool = True

    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_use_tls: bool = True
    smtp_from: str = ""

    @property
    def tz(self) -> ZoneInfo:
        return ZoneInfo(self.timezone)

    @property
    def report_hour_minute(self) -> tuple[int, int]:
        hour, minute = self.report_time.split(":")
        return int(hour), int(minute)

    @property
    def smtp_configured(self) -> bool:
        return bool(self.smtp_host and self.report_recipients)

    @classmethod
    def from_env(cls) -> "Config":
        load_dotenv(BASE_DIR / ".env")
        env = os.environ
        db_path = env.get("DATABASE_PATH", "heures.db")
        if not os.path.isabs(db_path):
            db_path = str(BASE_DIR / db_path)
        recipients = [r.strip() for r in env.get("REPORT_RECIPIENTS", "").split(",") if r.strip()]
        cfg = cls(
            secret_key=env.get("SECRET_KEY", cls.secret_key),
            database_path=db_path,
            timezone=env.get("TIMEZONE", cls.timezone),
            company_name=env.get("COMPANY_NAME", cls.company_name),
            report_time=env.get("REPORT_TIME", cls.report_time),
            report_recipients=recipients,
            scheduler_enabled=_bool(env.get("SCHEDULER_ENABLED"), True),
            smtp_host=env.get("SMTP_HOST", ""),
            smtp_port=int(env.get("SMTP_PORT", "587")),
            smtp_user=env.get("SMTP_USER", ""),
            smtp_password=env.get("SMTP_PASSWORD", ""),
            smtp_use_tls=_bool(env.get("SMTP_USE_TLS"), True),
            smtp_from=env.get("SMTP_FROM", "") or env.get("SMTP_USER", ""),
        )
        cfg.report_hour_minute  # valide le format HH:MM dès le démarrage
        return cfg

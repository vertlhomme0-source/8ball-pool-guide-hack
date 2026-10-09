"""Envoi du rapport par e-mail (SMTP)."""

from __future__ import annotations

import smtplib
import ssl
from datetime import date
from email.message import EmailMessage

from config import Config
from database import Database
from report import build_daily_report, render_csv, render_html, render_text


class MailError(RuntimeError):
    pass


def send_email(cfg: Config, subject: str, text: str, html: str,
               attachments: list[tuple[str, bytes, str]] | None = None) -> None:
    if not cfg.smtp_configured:
        raise MailError("SMTP non configuré : renseignez SMTP_HOST et REPORT_RECIPIENTS dans .env")

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = cfg.smtp_from or cfg.smtp_user
    msg["To"] = ", ".join(cfg.report_recipients)
    msg.set_content(text)
    msg.add_alternative(html, subtype="html")
    for filename, data, mimetype in attachments or []:
        maintype, subtype = mimetype.split("/", 1)
        msg.add_attachment(data, maintype=maintype, subtype=subtype, filename=filename)

    try:
        if cfg.smtp_port == 465:
            server = smtplib.SMTP_SSL(cfg.smtp_host, cfg.smtp_port, timeout=30,
                                      context=ssl.create_default_context())
        else:
            server = smtplib.SMTP(cfg.smtp_host, cfg.smtp_port, timeout=30)
        with server:
            if cfg.smtp_port != 465 and cfg.smtp_use_tls:
                server.starttls(context=ssl.create_default_context())
            if cfg.smtp_user:
                server.login(cfg.smtp_user, cfg.smtp_password)
            server.send_message(msg)
    except (smtplib.SMTPException, OSError) as exc:
        raise MailError(f"Échec de l'envoi : {exc}") from exc


def send_daily_report(cfg: Config, db: Database, day: date, automatic: bool = False) -> None:
    """Construit et envoie le rapport du jour, puis consigne le résultat dans la base."""
    report = build_daily_report(db, day, cfg.company_name)
    try:
        send_email(
            cfg,
            subject=report.subject,
            text=render_text(report),
            html=render_html(report),
            attachments=[(f"heures_{day.isoformat()}.csv", render_csv(report), "text/csv")],
        )
    except MailError as exc:
        db.log_report(day, cfg.report_recipients, ok=False, detail=str(exc), automatic=automatic)
        raise
    db.log_report(day, cfg.report_recipients, ok=True, automatic=automatic)

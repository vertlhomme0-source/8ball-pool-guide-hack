import sys
from datetime import date, datetime, time
from email import message_from_bytes
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mailer  # noqa: E402
from app import create_app  # noqa: E402
from config import Config  # noqa: E402
from database import Database, ValidationError, compute_worked_minutes  # noqa: E402
from report import build_daily_report, fmt_hours, render_csv, render_html  # noqa: E402
from scheduler import DailyReportScheduler  # noqa: E402

DAY = date(2026, 10, 9)  # un vendredi


@pytest.fixture
def cfg(tmp_path):
    return Config(database_path=str(tmp_path / "test.db"), company_name="Test Inc",
                  report_time="18:00", report_recipients=["patron@exemple.com"],
                  smtp_host="smtp.exemple.com", smtp_user="u", smtp_password="p")


@pytest.fixture
def db(cfg):
    return Database(cfg.database_path)


@pytest.fixture
def sent(monkeypatch):
    """Remplace le serveur SMTP par un faux qui mémorise les messages envoyés."""
    outbox = []

    class FakeSMTP:
        def __init__(self, *a, **kw): pass
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def starttls(self, **kw): pass
        def login(self, user, pwd): pass
        def send_message(self, msg): outbox.append(msg)

    monkeypatch.setattr(mailer.smtplib, "SMTP", FakeSMTP)
    return outbox


# ---------------------------------------------------------------- Calculs

def test_worked_minutes_normal_and_overnight():
    assert compute_worked_minutes(time(8), time(17), 60) == 8 * 60
    assert compute_worked_minutes(time(22), time(6), 30) == 7 * 60 + 30


def test_fmt_hours():
    assert fmt_hours(7.5) == "7 h 30"
    assert fmt_hours(0) == "0 h 00"


@pytest.mark.parametrize("start,end,pause,msg", [
    ("08:00", "08:00", 0, "identiques"),
    ("08:00", "09:00", 90, "pause"),
    ("8h", "09:00", 0, "Heure d'arrivée"),
    ("00:00", "23:00", 0, "16 h"),
])
def test_entry_validation(db, start, end, pause, msg):
    emp = db.add_employee("Ana")
    with pytest.raises(ValidationError, match=msg):
        db.add_entry(emp, DAY.isoformat(), start, end, pause)


def test_duplicate_employee_rejected(db):
    db.add_employee("Ana")
    with pytest.raises(ValidationError, match="existe déjà"):
        db.add_employee("Ana")


# ---------------------------------------------------------------- Rapport

def test_daily_report_totals_week_and_absents(db):
    ana = db.add_employee("Ana", hourly_rate=20)
    bob = db.add_employee("Bob", hourly_rate=15)
    db.add_employee("Chloé")
    db.add_entry(ana, "2026-10-05", "08:00", "18:00", 0)          # lundi, même semaine
    db.add_entry(ana, DAY.isoformat(), "08:00", "18:00", 30)      # 9.5 h
    db.add_entry(bob, DAY.isoformat(), "22:00", "02:00", 0)       # 4 h de nuit
    db.add_entry(bob, "2026-10-02", "08:00", "12:00", 0)          # semaine précédente

    r = build_daily_report(db, DAY, "Test Inc")
    assert r.total_hours == 13.5
    assert r.total_cost == 9.5 * 20 + 4 * 15
    ana_s, bob_s = r.summaries
    assert ana_s.daily_overtime and ana_s.week_hours == 19.5
    assert bob_s.week_hours == 4
    assert r.absent == ["Chloé"]

    html = render_html(r)
    assert "Ana" in html and "13 h 30" in html and "Chloé" in html
    csv_text = render_csv(r).decode("utf-8-sig")
    assert "Bob;22:00;02:00;0;4,00;60,00" in csv_text


def test_report_escapes_html(db):
    emp = db.add_employee("<script>x</script>")
    db.add_entry(emp, DAY.isoformat(), "08:00", "09:00", 0, "<b>")
    html = render_html(build_daily_report(db, DAY, "T"))
    assert "<script>" not in html and "&lt;b&gt;" in html


# ---------------------------------------------------------------- E-mail et planificateur

def test_send_daily_report_builds_email_with_csv(cfg, db, sent):
    emp = db.add_employee("Ana")
    db.add_entry(emp, DAY.isoformat(), "09:00", "17:00", 60)
    mailer.send_daily_report(cfg, db, DAY)

    assert len(sent) == 1
    msg = message_from_bytes(sent[0].as_bytes())
    assert msg["To"] == "patron@exemple.com"
    assert "7 h 00" in msg["Subject"]
    names = [p.get_filename() for p in msg.walk() if p.get_filename()]
    assert names == ["heures_2026-10-09.csv"]
    assert db.recent_reports()[0]["status"] == "ok"


def test_unconfigured_smtp_is_logged_as_error(cfg, db):
    cfg.smtp_host = ""
    with pytest.raises(mailer.MailError):
        mailer.send_daily_report(cfg, db, DAY)
    assert db.recent_reports()[0]["status"] == "erreur"


def test_scheduler_sends_once_after_report_time(cfg, db, sent):
    sched = DailyReportScheduler(cfg, db)
    assert not sched.tick(datetime(2026, 10, 9, 17, 59))
    assert sched.tick(datetime(2026, 10, 9, 18, 0))
    assert not sched.tick(datetime(2026, 10, 9, 18, 1))   # pas de doublon
    assert sched.tick(datetime(2026, 10, 10, 18, 0))      # le lendemain
    assert len(sent) == 2


def test_scheduler_retries_after_failure(cfg, db, monkeypatch, sent):
    calls = {"n": 0}
    real = mailer.send_email

    def flaky(*a, **kw):
        calls["n"] += 1
        if calls["n"] == 1:
            raise mailer.MailError("serveur indisponible")
        return real(*a, **kw)

    monkeypatch.setattr(mailer, "send_email", flaky)
    sched = DailyReportScheduler(cfg, db)
    assert not sched.tick(datetime(2026, 10, 9, 18, 0))
    assert not sched.tick(datetime(2026, 10, 9, 18, 5))   # attend 15 min avant de réessayer
    assert sched.tick(datetime(2026, 10, 9, 18, 16))
    assert len(sent) == 1


# ---------------------------------------------------------------- Pages web

def test_web_flow(cfg, sent):
    app = create_app(cfg)
    client = app.test_client()

    client.post("/employes", data={"name": "Ana", "role": "Vente", "hourly_rate": "18"})
    emp_id = app.config["HOURS_DB"].list_employees()[0].id
    r = client.post("/pointages", data={"employee_id": emp_id, "work_date": DAY.isoformat(),
                                        "start_time": "09:00", "end_time": "17:30",
                                        "break_minutes": "30"}, follow_redirects=True)
    assert "Heures enregistrées" in r.get_data(as_text=True)
    assert "8 h 00" in client.get(f"/?date={DAY}").get_data(as_text=True)

    r = client.post("/pointages", data={"employee_id": emp_id, "work_date": DAY.isoformat(),
                                        "start_time": "09:00", "end_time": "09:00"},
                    follow_redirects=True)
    assert "identiques" in r.get_data(as_text=True)

    for path in ("/historique", f"/rapport?date={DAY}", f"/rapport/apercu?date={DAY}",
                 f"/rapport/csv?date={DAY}"):
        assert client.get(path).status_code == 200, path

    r = client.post("/rapport/envoyer", data={"date": DAY.isoformat()}, follow_redirects=True)
    assert "Rapport envoyé" in r.get_data(as_text=True)
    assert len(sent) == 1

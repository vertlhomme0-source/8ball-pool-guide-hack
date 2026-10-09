"""Application web de suivi des heures des employés.

Lancement :
    python app.py                         # serveur web + envoi automatique quotidien
    python app.py envoyer-rapport [DATE]  # envoie un rapport tout de suite (utile avec cron)
    python app.py demo                    # ajoute des données d'exemple
"""

from __future__ import annotations

import logging
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta

from flask import (Flask, Response, abort, flash, redirect, render_template, request,
                   url_for)

from config import Config
from database import Database, ValidationError, parse_date
from mailer import MailError, send_daily_report
from report import (build_daily_report, date_fr, fmt_hours, render_csv, render_html)
from scheduler import DailyReportScheduler

log = logging.getLogger(__name__)


def create_app(cfg: Config | None = None, start_scheduler: bool = False) -> Flask:
    cfg = cfg or Config.from_env()
    db = Database(cfg.database_path)

    app = Flask(__name__)
    app.secret_key = cfg.secret_key
    app.config["HOURS_CFG"] = cfg
    app.config["HOURS_DB"] = db
    app.jinja_env.globals.update(fmt_hours=fmt_hours, date_fr=date_fr)

    if start_scheduler and cfg.scheduler_enabled:
        scheduler = DailyReportScheduler(cfg, db)
        scheduler.start()
        app.config["HOURS_SCHEDULER"] = scheduler

    def today() -> date:
        return datetime.now(cfg.tz).date()

    def selected_day() -> date:
        raw = request.values.get("date")
        if not raw:
            return today()
        try:
            return parse_date(raw)
        except ValidationError:
            abort(400, "Date invalide")

    @app.context_processor
    def inject_globals():
        return {"company": cfg.company_name, "today": today(), "cfg": cfg}

    # ------------------------------------------------------------ Saisie

    @app.get("/")
    def index():
        day = selected_day()
        report = build_daily_report(db, day, cfg.company_name)
        return render_template(
            "index.html",
            day=day,
            prev_day=day - timedelta(days=1),
            next_day=day + timedelta(days=1),
            report=report,
            employees=db.list_employees(),
        )

    @app.post("/pointages")
    def add_entry():
        form = request.form
        try:
            db.add_entry(
                employee_id=form.get("employee_id"),
                work_date=form.get("work_date", ""),
                start_time=form.get("start_time", ""),
                end_time=form.get("end_time", ""),
                break_minutes=form.get("break_minutes", "0"),
                notes=form.get("notes", ""),
            )
            flash("Heures enregistrées.", "success")
        except ValidationError as exc:
            flash(str(exc), "error")
        return redirect(url_for("index", date=form.get("work_date") or None))

    @app.post("/pointages/<int:entry_id>/supprimer")
    def delete_entry(entry_id: int):
        db.delete_entry(entry_id)
        flash("Pointage supprimé.", "success")
        return redirect(url_for("index", date=request.form.get("date") or None))

    # ------------------------------------------------------------ Employés

    @app.route("/employes", methods=["GET", "POST"])
    def employees():
        if request.method == "POST":
            try:
                db.add_employee(request.form.get("name", ""), request.form.get("role", ""),
                                request.form.get("hourly_rate", "0"))
                flash("Employé ajouté.", "success")
            except ValidationError as exc:
                flash(str(exc), "error")
            return redirect(url_for("employees"))
        return render_template("employees.html", employees=db.list_employees(include_inactive=True))

    @app.post("/employes/<int:employee_id>/statut")
    def toggle_employee(employee_id: int):
        db.set_employee_active(employee_id, request.form.get("active") == "1")
        return redirect(url_for("employees"))

    # ------------------------------------------------------------ Rapport

    @app.get("/rapport")
    def report_page():
        day = selected_day()
        return render_template("report.html", day=day, reports=db.recent_reports())

    @app.get("/rapport/apercu")
    def report_preview():
        return render_html(build_daily_report(db, selected_day(), cfg.company_name))

    @app.get("/rapport/csv")
    def report_csv():
        day = selected_day()
        data = render_csv(build_daily_report(db, day, cfg.company_name))
        return Response(data, mimetype="text/csv", headers={
            "Content-Disposition": f"attachment; filename=heures_{day.isoformat()}.csv"})

    @app.post("/rapport/envoyer")
    def report_send():
        day = selected_day()
        try:
            send_daily_report(cfg, db, day)
            flash(f"Rapport envoyé à {', '.join(cfg.report_recipients)}.", "success")
        except MailError as exc:
            flash(str(exc), "error")
        return redirect(url_for("report_page", date=day.isoformat()))

    # ------------------------------------------------------------ Historique

    @app.get("/historique")
    def history():
        end = today()
        start = end - timedelta(days=13)
        try:
            if request.args.get("fin"):
                end = parse_date(request.args["fin"])
            if request.args.get("debut"):
                start = parse_date(request.args["debut"])
        except ValidationError as exc:
            flash(str(exc), "error")
        if start > end:
            start, end = end, start
        if (end - start).days > 92:
            start = end - timedelta(days=92)
            flash("Période limitée à 3 mois.", "error")

        days = [start + timedelta(days=i) for i in range((end - start).days + 1)]
        grid: dict[str, dict[date, float]] = defaultdict(lambda: defaultdict(float))
        for e in db.entries_between(start, end):
            grid[e.employee_name][e.work_date] += e.hours
        names = sorted(grid, key=str.lower)
        return render_template("history.html", start=start, end=end, days=days,
                               grid=grid, names=names)

    return app


# ---------------------------------------------------------------- CLI

def seed_demo(db: Database, day: date) -> None:
    demo = [("Marie Tremblay", "Gérante", 28), ("Jean Gagnon", "Caissier", 17.5),
            ("Sofia Nguyen", "Cuisinière", 20), ("Karim Benali", "Livreur", 16.75)]
    ids = {}
    for name, role, rate in demo:
        try:
            ids[name] = db.add_employee(name, role, rate)
        except ValidationError:
            ids[name] = next(e.id for e in db.list_employees(True) if e.name == name)
    for offset in range(5, -1, -1):
        d = (day - timedelta(days=offset)).isoformat()
        db.add_entry(ids["Marie Tremblay"], d, "08:00", "17:30", 60, "Ouverture")
        db.add_entry(ids["Jean Gagnon"], d, "09:00", "13:00", 0)
        db.add_entry(ids["Jean Gagnon"], d, "14:00", "18:15", 15)
        if offset % 2 == 0:
            db.add_entry(ids["Sofia Nguyen"], d, "22:00", "06:00", 30, "Quart de nuit")


def main(argv: list[str]) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    cfg = Config.from_env()

    if argv and argv[0] == "envoyer-rapport":
        db = Database(cfg.database_path)
        day = parse_date(argv[1]) if len(argv) > 1 else datetime.now(cfg.tz).date()
        try:
            send_daily_report(cfg, db, day)
        except MailError as exc:
            print(exc, file=sys.stderr)
            return 1
        print(f"Rapport du {day} envoyé à {', '.join(cfg.report_recipients)}")
        return 0

    if argv and argv[0] == "demo":
        seed_demo(Database(cfg.database_path), datetime.now(cfg.tz).date())
        print("Données d'exemple ajoutées.")
        return 0

    app = create_app(cfg, start_scheduler=True)
    if not cfg.smtp_configured:
        log.warning("SMTP non configuré : le rapport automatique ne pourra pas partir (voir .env)")
    # use_reloader=False : sinon le planificateur tournerait dans deux processus
    app.run(host="0.0.0.0", port=5000, debug=False, use_reloader=False)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

"""Construction du rapport journalier (données, e-mail HTML/texte et pièce jointe CSV)."""

from __future__ import annotations

import csv
import io
from dataclasses import dataclass, field
from datetime import date, timedelta
from html import escape

from database import Database, TimeEntry

DAILY_OVERTIME_HOURS = 8
WEEKLY_OVERTIME_HOURS = 40

JOURS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
MOIS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet",
        "août", "septembre", "octobre", "novembre", "décembre"]


def date_fr(day: date) -> str:
    return f"{JOURS[day.weekday()]} {day.day} {MOIS[day.month - 1]} {day.year}"


def fmt_hours(hours: float) -> str:
    """7.5 -> '7 h 30'."""
    total = round(hours * 60)
    return f"{total // 60} h {total % 60:02d}"


@dataclass
class EmployeeSummary:
    employee_id: int
    name: str
    entries: list[TimeEntry] = field(default_factory=list)
    week_hours: float = 0.0

    @property
    def day_hours(self) -> float:
        return round(sum(e.hours for e in self.entries), 2)

    @property
    def day_cost(self) -> float:
        return round(sum(e.cost for e in self.entries), 2)

    @property
    def daily_overtime(self) -> bool:
        return self.day_hours > DAILY_OVERTIME_HOURS

    @property
    def weekly_overtime(self) -> bool:
        return self.week_hours > WEEKLY_OVERTIME_HOURS


@dataclass
class DailyReport:
    day: date
    company: str
    summaries: list[EmployeeSummary]
    absent: list[str]

    @property
    def entries(self) -> list[TimeEntry]:
        return [e for s in self.summaries for e in s.entries]

    @property
    def total_hours(self) -> float:
        return round(sum(s.day_hours for s in self.summaries), 2)

    @property
    def total_cost(self) -> float:
        return round(sum(s.day_cost for s in self.summaries), 2)

    @property
    def subject(self) -> str:
        return (f"[{self.company}] Rapport des heures – {date_fr(self.day)} – "
                f"{fmt_hours(self.total_hours)} au total")


def build_daily_report(db: Database, day: date, company: str) -> DailyReport:
    week_start = day - timedelta(days=day.weekday())  # lundi
    week_entries = db.entries_between(week_start, day)

    summaries: dict[int, EmployeeSummary] = {}
    week_totals: dict[int, float] = {}
    for entry in week_entries:
        week_totals[entry.employee_id] = week_totals.get(entry.employee_id, 0) + entry.hours
        if entry.work_date == day:
            summaries.setdefault(
                entry.employee_id, EmployeeSummary(entry.employee_id, entry.employee_name)
            ).entries.append(entry)

    for s in summaries.values():
        s.week_hours = round(week_totals.get(s.employee_id, 0), 2)

    present = set(summaries)
    absent = [e.name for e in db.list_employees() if e.id not in present]
    ordered = sorted(summaries.values(), key=lambda s: s.name.lower())
    return DailyReport(day=day, company=company, summaries=ordered, absent=absent)


# ---------------------------------------------------------------- Rendus

def render_csv(report: DailyReport) -> bytes:
    buf = io.StringIO()
    writer = csv.writer(buf, delimiter=";")
    writer.writerow(["Date", "Employé", "Arrivée", "Départ", "Pause (min)",
                     "Heures", "Coût", "Notes"])
    for e in report.entries:
        writer.writerow([e.work_date.isoformat(), e.employee_name,
                         e.start_time.strftime("%H:%M"), e.end_time.strftime("%H:%M"),
                         e.break_minutes, f"{e.hours:.2f}".replace(".", ","),
                         f"{e.cost:.2f}".replace(".", ","), e.notes])
    writer.writerow([])
    writer.writerow(["TOTAL", "", "", "", "", f"{report.total_hours:.2f}".replace(".", ","),
                     f"{report.total_cost:.2f}".replace(".", ","), ""])
    # BOM UTF-8 pour qu'Excel affiche correctement les accents
    return buf.getvalue().encode("utf-8-sig")


def render_text(report: DailyReport) -> str:
    lines = [f"Rapport des heures – {date_fr(report.day)}", f"{report.company}", ""]
    if not report.summaries:
        lines.append("Aucune heure saisie aujourd'hui.")
    for s in report.summaries:
        flag = " (heures sup.)" if s.daily_overtime else ""
        lines.append(f"- {s.name} : {fmt_hours(s.day_hours)}{flag} "
                     f"| semaine : {fmt_hours(s.week_hours)}")
        for e in s.entries:
            note = f" – {e.notes}" if e.notes else ""
            lines.append(f"    {e.start_time:%H:%M} → {e.end_time:%H:%M}, "
                         f"pause {e.break_minutes} min{note}")
    lines += ["", f"Total : {fmt_hours(report.total_hours)}  |  Coût : {report.total_cost:.2f} $"]
    if report.absent:
        lines.append(f"Sans pointage : {', '.join(report.absent)}")
    return "\n".join(lines)


def render_html(report: DailyReport) -> str:
    """HTML d'e-mail (styles en ligne, compatible avec Gmail/Outlook)."""
    td = "padding:8px 10px;border-bottom:1px solid #e5e7eb;"
    th = "padding:8px 10px;text-align:left;background:#f3f4f6;font-weight:600;font-size:13px;"
    badge = ("display:inline-block;padding:1px 6px;border-radius:4px;font-size:11px;"
             "background:#fef3c7;color:#92400e;margin-left:6px;")

    rows = []
    for s in report.summaries:
        for i, e in enumerate(s.entries):
            name_cell = escape(s.name) if i == 0 else ""
            if i == 0 and s.daily_overtime:
                name_cell += f'<span style="{badge}">+{DAILY_OVERTIME_HOURS} h</span>'
            night = " 🌙" if e.overnight else ""
            rows.append(
                f"<tr><td style='{td}'>{name_cell}</td>"
                f"<td style='{td}'>{e.start_time:%H:%M} → {e.end_time:%H:%M}{night}</td>"
                f"<td style='{td}'>{e.break_minutes} min</td>"
                f"<td style='{td}text-align:right'>{fmt_hours(e.hours)}</td>"
                f"<td style='{td}color:#6b7280'>{escape(e.notes)}</td></tr>"
            )
        week_style = "color:#b45309;font-weight:600" if s.weekly_overtime else "color:#6b7280"
        rows.append(
            f"<tr><td style='{td}' colspan='3'><em style='color:#6b7280'>Sous-total "
            f"{escape(s.name)} – semaine : <span style='{week_style}'>{fmt_hours(s.week_hours)}"
            f"</span></em></td><td style='{td}text-align:right;font-weight:600'>"
            f"{fmt_hours(s.day_hours)}</td><td style='{td}'></td></tr>"
        )
    if not rows:
        rows.append(f"<tr><td style='{td}' colspan='5'>Aucune heure saisie pour cette journée.</td></tr>")

    absent_html = ""
    if report.absent:
        absent_html = (f"<p style='margin:16px 0 0;color:#6b7280;font-size:13px'>"
                       f"<strong>Sans pointage :</strong> {escape(', '.join(report.absent))}</p>")

    def card(label: str, value: str) -> str:
        return (f"<td style='padding:12px 16px;background:#f9fafb;border-radius:8px;width:33%'>"
                f"<div style='font-size:12px;color:#6b7280'>{label}</div>"
                f"<div style='font-size:20px;font-weight:700;color:#111827'>{value}</div></td>")

    return f"""<!doctype html>
<html lang="fr"><body style="margin:0;background:#f3f4f6;font-family:Segoe UI,Arial,sans-serif;color:#111827">
<div style="max-width:720px;margin:0 auto;padding:24px">
 <div style="background:#ffffff;border-radius:12px;padding:24px">
  <div style="font-size:13px;color:#6b7280">{escape(report.company)}</div>
  <h1 style="margin:4px 0 20px;font-size:22px">Rapport des heures – {date_fr(report.day)}</h1>
  <table role="presentation" width="100%" cellspacing="8" style="margin:0 -8px 16px">
   <tr>{card("Heures totales", fmt_hours(report.total_hours))}
       {card("Employés présents", str(len(report.summaries)))}
       {card("Coût estimé", f"{report.total_cost:.2f} $")}</tr>
  </table>
  <table width="100%" cellspacing="0" style="border-collapse:collapse;font-size:14px">
   <tr><th style="{th}">Employé</th><th style="{th}">Horaire</th><th style="{th}">Pause</th>
       <th style="{th}text-align:right">Heures</th><th style="{th}">Notes</th></tr>
   {''.join(rows)}
  </table>
  {absent_html}
  <p style="margin:24px 0 0;font-size:12px;color:#9ca3af">Le détail est joint au format CSV
   (ouvrable dans Excel). Rapport généré automatiquement.</p>
 </div>
</div></body></html>"""

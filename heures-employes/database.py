"""Accès aux données (SQLite) : employés, pointages et journal des rapports envoyés."""

from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Iterator

SCHEMA = """
CREATE TABLE IF NOT EXISTS employees (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    role        TEXT NOT NULL DEFAULT '',
    hourly_rate REAL NOT NULL DEFAULT 0,
    active      INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS time_entries (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id   INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    work_date     TEXT NOT NULL,           -- AAAA-MM-JJ
    start_time    TEXT NOT NULL,           -- HH:MM
    end_time      TEXT NOT NULL,           -- HH:MM (peut être le lendemain : quart de nuit)
    break_minutes INTEGER NOT NULL DEFAULT 0,
    notes         TEXT NOT NULL DEFAULT '',
    created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_entries_date ON time_entries(work_date);

CREATE TABLE IF NOT EXISTS report_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    report_date TEXT NOT NULL,
    sent_at     TEXT NOT NULL,
    recipients  TEXT NOT NULL,
    status      TEXT NOT NULL,             -- 'ok' ou 'erreur'
    detail      TEXT NOT NULL DEFAULT '',
    automatic   INTEGER NOT NULL DEFAULT 0
);
"""


class ValidationError(ValueError):
    """Donnée saisie invalide (message affichable à l'utilisateur)."""


@dataclass(frozen=True)
class Employee:
    id: int
    name: str
    role: str
    hourly_rate: float
    active: bool


@dataclass(frozen=True)
class TimeEntry:
    id: int
    employee_id: int
    employee_name: str
    work_date: date
    start_time: time
    end_time: time
    break_minutes: int
    notes: str
    hourly_rate: float

    @property
    def worked_minutes(self) -> int:
        return compute_worked_minutes(self.start_time, self.end_time, self.break_minutes)

    @property
    def hours(self) -> float:
        return round(self.worked_minutes / 60, 2)

    @property
    def cost(self) -> float:
        return round(self.hours * self.hourly_rate, 2)

    @property
    def overnight(self) -> bool:
        return self.end_time <= self.start_time


def compute_worked_minutes(start: time, end: time, break_minutes: int) -> int:
    """Minutes travaillées ; si la fin est avant le début, le quart se termine le lendemain."""
    start_dt = datetime.combine(date.min, start)
    end_dt = datetime.combine(date.min, end)
    if end_dt <= start_dt:
        end_dt += timedelta(days=1)
    return int((end_dt - start_dt).total_seconds() // 60) - break_minutes


def parse_time(value: str, label: str) -> time:
    try:
        return datetime.strptime(value.strip(), "%H:%M").time()
    except (ValueError, AttributeError):
        raise ValidationError(f"{label} invalide (format attendu HH:MM).") from None


def parse_date(value: str) -> date:
    try:
        return date.fromisoformat(value.strip())
    except (ValueError, AttributeError):
        raise ValidationError("Date invalide (format attendu AAAA-MM-JJ).") from None


class Database:
    def __init__(self, path: str):
        self.path = path
        with self.connect() as conn:
            conn.executescript(SCHEMA)

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    # ---------- Employés ----------

    def add_employee(self, name: str, role: str = "", hourly_rate: float | str = 0) -> int:
        name = (name or "").strip()
        if not name:
            raise ValidationError("Le nom de l'employé est obligatoire.")
        try:
            rate = float(hourly_rate or 0)
        except ValueError:
            raise ValidationError("Taux horaire invalide.") from None
        if rate < 0:
            raise ValidationError("Le taux horaire ne peut pas être négatif.")
        try:
            with self.connect() as conn:
                cur = conn.execute(
                    "INSERT INTO employees (name, role, hourly_rate) VALUES (?, ?, ?)",
                    (name, (role or "").strip(), rate),
                )
                return cur.lastrowid
        except sqlite3.IntegrityError:
            raise ValidationError(f"Un employé nommé « {name} » existe déjà.") from None

    def list_employees(self, include_inactive: bool = False) -> list[Employee]:
        sql = "SELECT * FROM employees"
        if not include_inactive:
            sql += " WHERE active = 1"
        sql += " ORDER BY name COLLATE NOCASE"
        with self.connect() as conn:
            return [
                Employee(r["id"], r["name"], r["role"], r["hourly_rate"], bool(r["active"]))
                for r in conn.execute(sql)
            ]

    def set_employee_active(self, employee_id: int, active: bool) -> None:
        with self.connect() as conn:
            conn.execute("UPDATE employees SET active = ? WHERE id = ?", (int(active), employee_id))

    # ---------- Pointages ----------

    def add_entry(
        self,
        employee_id: int | str,
        work_date: str,
        start_time: str,
        end_time: str,
        break_minutes: int | str = 0,
        notes: str = "",
    ) -> int:
        try:
            emp_id = int(employee_id)
        except (TypeError, ValueError):
            raise ValidationError("Veuillez choisir un employé.") from None
        day = parse_date(work_date)
        start = parse_time(start_time, "Heure d'arrivée")
        end = parse_time(end_time, "Heure de départ")
        try:
            pause = int(break_minutes or 0)
        except ValueError:
            raise ValidationError("La pause doit être un nombre de minutes.") from None
        if pause < 0:
            raise ValidationError("La pause ne peut pas être négative.")
        if start == end:
            raise ValidationError("L'heure d'arrivée et de départ sont identiques.")
        worked = compute_worked_minutes(start, end, pause)
        if worked <= 0:
            raise ValidationError("La pause est plus longue que le quart de travail.")
        if worked > 16 * 60:
            raise ValidationError("Un quart de plus de 16 h semble être une erreur de saisie.")

        with self.connect() as conn:
            if not conn.execute("SELECT 1 FROM employees WHERE id = ?", (emp_id,)).fetchone():
                raise ValidationError("Employé introuvable.")
            cur = conn.execute(
                """INSERT INTO time_entries
                   (employee_id, work_date, start_time, end_time, break_minutes, notes)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (emp_id, day.isoformat(), start.strftime("%H:%M"), end.strftime("%H:%M"),
                 pause, (notes or "").strip()),
            )
            return cur.lastrowid

    def delete_entry(self, entry_id: int) -> None:
        with self.connect() as conn:
            conn.execute("DELETE FROM time_entries WHERE id = ?", (entry_id,))

    def entries_between(self, start: date, end: date) -> list[TimeEntry]:
        """Pointages entre deux dates incluses, triés par date puis employé."""
        with self.connect() as conn:
            rows = conn.execute(
                """SELECT t.*, e.name AS employee_name, e.hourly_rate
                   FROM time_entries t JOIN employees e ON e.id = t.employee_id
                   WHERE t.work_date BETWEEN ? AND ?
                   ORDER BY t.work_date, e.name COLLATE NOCASE, t.start_time""",
                (start.isoformat(), end.isoformat()),
            ).fetchall()
        return [
            TimeEntry(
                id=r["id"],
                employee_id=r["employee_id"],
                employee_name=r["employee_name"],
                work_date=date.fromisoformat(r["work_date"]),
                start_time=time.fromisoformat(r["start_time"]),
                end_time=time.fromisoformat(r["end_time"]),
                break_minutes=r["break_minutes"],
                notes=r["notes"],
                hourly_rate=r["hourly_rate"],
            )
            for r in rows
        ]

    def entries_for_day(self, day: date) -> list[TimeEntry]:
        return self.entries_between(day, day)

    # ---------- Journal des rapports ----------

    def log_report(self, report_date: date, recipients: list[str], ok: bool,
                   detail: str = "", automatic: bool = False) -> None:
        with self.connect() as conn:
            conn.execute(
                """INSERT INTO report_log (report_date, sent_at, recipients, status, detail, automatic)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (report_date.isoformat(), datetime.now().isoformat(timespec="seconds"),
                 ", ".join(recipients), "ok" if ok else "erreur", detail, int(automatic)),
            )

    def report_sent_automatically(self, report_date: date) -> bool:
        with self.connect() as conn:
            return conn.execute(
                "SELECT 1 FROM report_log WHERE report_date = ? AND automatic = 1 AND status = 'ok'",
                (report_date.isoformat(),),
            ).fetchone() is not None

    def recent_reports(self, limit: int = 20) -> list[sqlite3.Row]:
        with self.connect() as conn:
            return conn.execute(
                "SELECT * FROM report_log ORDER BY id DESC LIMIT ?", (limit,)
            ).fetchall()

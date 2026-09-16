"""Journal de trading persistant (SQLite).

Sert a trois usages : tracer ce que le bot a fait et pourquoi, calculer les
statistiques (taux de reussite, facteur de profit, drawdown), et reconstruire
la courbe d'equity apres un redemarrage.
"""

from __future__ import annotations

import sqlite3
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from ..config import DB_PATH

_SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ts          TEXT    NOT NULL,
    level       TEXT    NOT NULL,
    category    TEXT    NOT NULL,
    symbol      TEXT,
    message     TEXT    NOT NULL
);
CREATE TABLE IF NOT EXISTS trades (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket        INTEGER,
    symbol        TEXT    NOT NULL,
    side          TEXT    NOT NULL,
    volume        REAL    NOT NULL,
    price_open    REAL    NOT NULL,
    sl            REAL,
    tp            REAL,
    opened_at     TEXT    NOT NULL,
    closed_at     TEXT,
    price_close   REAL,
    profit        REAL,
    close_reason  TEXT,
    strategy      TEXT,
    reason        TEXT,
    confidence    REAL,
    simulated     INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS equity (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    ts       TEXT NOT NULL,
    balance  REAL NOT NULL,
    equity   REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_ts  ON events(ts);
CREATE INDEX IF NOT EXISTS idx_trades_tkt ON trades(ticket);
CREATE INDEX IF NOT EXISTS idx_equity_ts  ON equity(ts);
"""


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Journal:
    """Acces SQLite serialise par un verrou : utilisable depuis plusieurs threads."""

    def __init__(self, path: Path = DB_PATH):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._conn = sqlite3.connect(str(self.path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        with self._lock:
            self._conn.executescript(_SCHEMA)
            self._conn.commit()

    def close(self) -> None:
        with self._lock:
            self._conn.close()

    # ------------------------------------------------------------ ecriture --
    def log(self, level: str, category: str, message: str, symbol: str = "") -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO events (ts, level, category, symbol, message) VALUES (?,?,?,?,?)",
                (_now(), level, category, symbol, message),
            )
            self._conn.commit()

    def record_open(
        self,
        ticket: int,
        symbol: str,
        side: str,
        volume: float,
        price_open: float,
        sl: float,
        tp: float,
        strategy: str,
        reason: str,
        confidence: float,
        simulated: bool,
    ) -> None:
        with self._lock:
            self._conn.execute(
                """INSERT INTO trades
                   (ticket, symbol, side, volume, price_open, sl, tp, opened_at,
                    strategy, reason, confidence, simulated)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
                (ticket, symbol, side, volume, price_open, sl, tp, _now(),
                 strategy, reason, confidence, int(simulated)),
            )
            self._conn.commit()

    def record_close(
        self, ticket: int, price_close: float, profit: float, reason: str
    ) -> None:
        with self._lock:
            self._conn.execute(
                """UPDATE trades
                   SET closed_at = ?, price_close = ?, profit = ?, close_reason = ?
                   WHERE ticket = ? AND closed_at IS NULL""",
                (_now(), price_close, profit, reason, ticket),
            )
            self._conn.commit()

    def record_equity(self, balance: float, equity: float) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO equity (ts, balance, equity) VALUES (?,?,?)",
                (_now(), balance, equity),
            )
            self._conn.commit()

    def has_open_ticket(self, ticket: int) -> bool:
        with self._lock:
            row = self._conn.execute(
                "SELECT 1 FROM trades WHERE ticket = ? AND closed_at IS NULL", (ticket,)
            ).fetchone()
            return row is not None

    # ------------------------------------------------------------ lecture ---
    def recent_events(self, limit: int = 300) -> List[Dict[str, Any]]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT * FROM events ORDER BY id DESC LIMIT ?", (limit,)
            ).fetchall()
        return [dict(r) for r in reversed(rows)]

    def recent_trades(self, limit: int = 200) -> List[Dict[str, Any]]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT * FROM trades ORDER BY id DESC LIMIT ?", (limit,)
            ).fetchall()
        return [dict(r) for r in rows]

    def equity_curve(self, limit: int = 5000) -> List[Dict[str, Any]]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT ts, balance, equity FROM equity ORDER BY id DESC LIMIT ?", (limit,)
            ).fetchall()
        return [dict(r) for r in reversed(rows)]

    def statistics(self) -> Dict[str, float]:
        """Statistiques sur les trades clotures enregistres par le bot."""
        with self._lock:
            rows = self._conn.execute(
                "SELECT profit FROM trades WHERE closed_at IS NOT NULL AND profit IS NOT NULL"
            ).fetchall()
        profits = [float(r["profit"]) for r in rows]
        if not profits:
            return {
                "trades": 0, "wins": 0, "losses": 0, "win_rate": 0.0,
                "gross_profit": 0.0, "gross_loss": 0.0, "net": 0.0,
                "profit_factor": 0.0, "expectancy": 0.0,
                "avg_win": 0.0, "avg_loss": 0.0, "max_drawdown": 0.0,
            }
        wins = [p for p in profits if p > 0]
        losses = [p for p in profits if p < 0]
        gross_profit = sum(wins)
        gross_loss = abs(sum(losses))
        # Drawdown sur la courbe cumulee des trades fermes
        cumulative, peak, max_dd = 0.0, 0.0, 0.0
        for p in profits:
            cumulative += p
            peak = max(peak, cumulative)
            max_dd = max(max_dd, peak - cumulative)
        return {
            "trades": len(profits),
            "wins": len(wins),
            "losses": len(losses),
            "win_rate": len(wins) / len(profits) * 100.0,
            "gross_profit": gross_profit,
            "gross_loss": gross_loss,
            "net": gross_profit - gross_loss,
            "profit_factor": (gross_profit / gross_loss) if gross_loss > 0 else float("inf"),
            "expectancy": sum(profits) / len(profits),
            "avg_win": (gross_profit / len(wins)) if wins else 0.0,
            "avg_loss": (gross_loss / len(losses)) if losses else 0.0,
            "max_drawdown": max_dd,
        }

    def purge(self) -> None:
        with self._lock:
            self._conn.executescript(
                "DELETE FROM events; DELETE FROM trades; DELETE FROM equity;"
            )
            self._conn.commit()

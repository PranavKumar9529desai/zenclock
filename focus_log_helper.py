#!/usr/bin/env python3
"""Focus Log write helper.

Reads newline-delimited JSON commands on stdin and writes one newline-delimited
JSON response per command on stdout. All SQL is parameterized and every write is
wrapped in an explicit transaction.

The published seam is the SQLite file and its documented schema, not this
helper: see docs/focus-log-schema.md.
"""

import json
import os
import sqlite3
import sys
import time

SCHEMA_VERSION = 1

SCHEMA = """
CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS focus_record (
  id TEXT PRIMARY KEY,
  duration_minutes INTEGER NOT NULL,
  recorded_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS cycle_record (
  id TEXT PRIMARY KEY,
  recorded_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS countdown_record (
  id TEXT PRIMARY KEY,
  duration_minutes INTEGER NOT NULL,
  recorded_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS checkpoint (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  phase TEXT NOT NULL,
  remaining_seconds INTEGER NOT NULL,
  session_number INTEGER NOT NULL,
  completed_focus_sessions INTEGER NOT NULL,
  saved_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS focus_log_policy (
  key TEXT PRIMARY KEY,
  value INTEGER NOT NULL
);
"""

COUNT_TABLES = {
    "focus": "focus_record",
    "cycle": "cycle_record",
    "countdown": "countdown_record",
}

# The three public record kinds are the only things a prune may delete. The
# checkpoint is deliberately absent: a paused Focus Session must stay resumable
# no matter how old it is (ADR 0003).
RECORD_TABLES = tuple(COUNT_TABLES.values())


def now_ms():
    return int(time.time() * 1000)


def degraded(op, reason):
    """A failed command: no record is written and the adapter stays alive.

    `status` is the observable storage status in the plugin state JSON; `error`
    carries the human-readable reason that the QML adapter logs.
    """
    return {"op": op, "ok": False, "status": "degraded", "error": str(reason)}


def connect(path):
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    conn = sqlite3.connect(path, timeout=5.0)
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def ensure_schema(conn):
    with conn:
        conn.executescript(SCHEMA)
        conn.execute(
            "INSERT OR IGNORE INTO schema_version (version, applied_at) VALUES (?, ?)",
            (SCHEMA_VERSION, now_ms()),
        )
        for key in ("checkpoint_ttl_days", "record_retention_days"):
            conn.execute(
                "INSERT OR IGNORE INTO focus_log_policy (key, value) VALUES (?, 0)",
                (key,),
            )


def prune(conn):
    """Delete only records older than the configured record retention.

    Pruning is an explicit operation, never automatic, and it never deletes
    the checkpoint: the default checkpoint policy is keep forever, so a
    months-old resumable session must survive a cleanup of old records.
    """
    row = conn.execute(
        "SELECT value FROM focus_log_policy WHERE key = 'record_retention_days'"
    ).fetchone()
    retention_days = row[0] if row else 0
    deleted = {table: 0 for table in RECORD_TABLES}
    if retention_days > 0:
        cutoff = now_ms() - retention_days * 86400 * 1000
        with conn:
            for table in RECORD_TABLES:
                cursor = conn.execute(
                    "DELETE FROM " + table + " WHERE recorded_at < ?", (cutoff,))
                deleted[table] = cursor.rowcount
    return deleted


def status_for(conn, path):
    version = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()[0]
    journal_mode = conn.execute("PRAGMA journal_mode").fetchone()[0]
    counts = {
        name: conn.execute("SELECT COUNT(*) FROM " + table).fetchone()[0]
        for name, table in COUNT_TABLES.items()
    }
    return {
        "ok": True,
        "status": "ok",
        "path": path,
        "version": version,
        "journalMode": journal_mode,
        "counts": counts,
    }


def handle(command):
    op = command.get("op")
    path = command.get("path")
    if not path:
        return degraded(op, "missing path")

    conn = None
    try:
        conn = connect(path)
        ensure_schema(conn)

        if op == "init":
            response = status_for(conn, path)
        elif op == "record_focus":
            with conn:
                cursor = conn.execute(
                    "INSERT OR IGNORE INTO focus_record "
                    "(id, duration_minutes, recorded_at) VALUES (?, ?, ?)",
                    (command["id"], int(command["durationMinutes"]),
                     int(command["timestamp"])),
                )
                inserted = cursor.rowcount
            response = status_for(conn, path)
            response["inserted"] = 1 if inserted > 0 else 0
        elif op == "status":
            response = status_for(conn, path)
        elif op == "prune":
            deleted = prune(conn)
            response = status_for(conn, path)
            response["deleted"] = deleted
        else:
            return degraded(op, "unknown op")

        response["op"] = op
        return response
    except Exception as exc:  # keep the helper alive for later commands
        return degraded(op, exc)
    finally:
        if conn is not None:
            conn.close()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            command = json.loads(line)
        except ValueError as exc:
            print(json.dumps(degraded(None, "invalid JSON: " + str(exc))), flush=True)
            continue
        print(json.dumps(handle(command)), flush=True)


if __name__ == "__main__":
    main()

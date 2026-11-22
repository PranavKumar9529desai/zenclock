#!/usr/bin/env python3
"""Unit tests for the Focus Log write helper.

These tests drive the helper through its public NDJSON interface and then read
the published artifact (the SQLite file) with an independent sqlite3 client.
They do not inspect helper internals.
"""

import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest

HELPER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "focus_log_helper.py")


def run_helper(commands):
    """Send NDJSON commands to the helper and return its NDJSON responses."""
    payload = "".join(json.dumps(c) + "\n" for c in commands)
    proc = subprocess.run([sys.executable, HELPER], input=payload, text=True,
                          capture_output=True, timeout=15)
    if proc.returncode != 0:
        raise AssertionError("helper failed: " + proc.stderr)
    return [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]


class FocusLogHelperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="zc-focus-log-test-")
        self.addCleanup(self.tmp.cleanup)
        self.db = os.path.join(self.tmp.name, "zenclock", "focus-log.sqlite3")

    def init(self):
        return run_helper([{"op": "init", "path": self.db, "version": 1}])[0]

    def test_init_creates_document_schema_and_wal(self):
        response = self.init()
        self.assertTrue(response["ok"])
        self.assertEqual(response["version"], 1)
        self.assertEqual(response["journalMode"].lower(), "wal")
        self.assertTrue(os.path.isfile(self.db))

        conn = sqlite3.connect(self.db)
        try:
            self.assertEqual(conn.execute("PRAGMA journal_mode").fetchone()[0].lower(), "wal")
            self.assertEqual(
                conn.execute("SELECT version FROM schema_version").fetchall(), [(1,)])
            for table in ("focus_record", "cycle_record", "countdown_record",
                          "checkpoint", "focus_log_policy"):
                row = conn.execute(
                    "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                    (table,)).fetchone()
                self.assertIsNotNone(row, "missing table " + table)
        finally:
            conn.close()

    def test_record_focus_persists_id_duration_and_timestamp(self):
        self.init()
        event = {"op": "record_focus", "path": self.db,
                 "id": "zc-test-f1", "durationMinutes": 25,
                 "timestamp": 1730000000123}
        response = run_helper([event])[0]

        self.assertTrue(response["ok"])
        self.assertEqual(response["inserted"], 1)
        conn = sqlite3.connect(self.db)
        try:
            rows = conn.execute(
                "SELECT id, duration_minutes, recorded_at FROM focus_record").fetchall()
        finally:
            conn.close()
        self.assertEqual(rows, [("zc-test-f1", 25, 1730000000123)])

    def test_redelivery_does_not_create_a_second_record(self):
        self.init()
        event = {"op": "record_focus", "path": self.db,
                 "id": "zc-test-f1", "durationMinutes": 25,
                 "timestamp": 1730000000123}
        responses = run_helper([event, event])

        self.assertEqual([r["inserted"] for r in responses], [1, 0])
        conn = sqlite3.connect(self.db)
        try:
            count = conn.execute("SELECT COUNT(*) FROM focus_record").fetchone()[0]
        finally:
            conn.close()
        self.assertEqual(count, 1)

    def test_status_reports_path_version_counts_and_storage_status(self):
        self.init()
        responses = run_helper([
            {"op": "record_focus", "path": self.db,
             "id": "zc-test-f1", "durationMinutes": 25, "timestamp": 1730000000123},
            {"op": "status", "path": self.db},
        ])
        status = responses[-1]

        self.assertTrue(status["ok"])
        self.assertEqual(status["status"], "ok")
        self.assertEqual(status["version"], 1)
        self.assertEqual(status["counts"], {"focus": 1, "cycle": 0, "countdown": 0})
        self.assertEqual(status["journalMode"].lower(), "wal")


if __name__ == "__main__":
    unittest.main()

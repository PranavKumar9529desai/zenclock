#!/usr/bin/env python3
"""Unit tests for the Focus Log write helper.

These tests drive the helper through its public NDJSON interface and then read
the published artifact (the SQLite file) with an independent sqlite3 client.
They do not inspect helper internals.
"""

import datetime
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest

# The published queries group by local day. Pin UTC so their day labels are
# deterministic without changing the SQL under test.
os.environ["TZ"] = "UTC"
time.tzset()

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

    def test_checkpoint_round_trip(self):
        self.init()
        saved = run_helper([{
            "op": "save_checkpoint", "path": self.db,
            "phase": "shortBreak", "remainingSeconds": 245,
            "sessionNumber": 2, "completedFocusSessions": 2,
        }])[0]
        self.assertTrue(saved["ok"])

        loaded = run_helper([{"op": "load_checkpoint", "path": self.db}])[0]
        self.assertTrue(loaded["ok"])
        checkpoint = dict(loaded["checkpoint"])
        self.assertIsInstance(checkpoint.pop("savedAt"), int)
        self.assertEqual(checkpoint, {
            "phase": "shortBreak", "remainingSeconds": 245,
            "sessionNumber": 2, "completedFocusSessions": 2,
        })

    def test_saving_twice_upserts_one_checkpoint(self):
        self.init()
        run_helper([
            {"op": "save_checkpoint", "path": self.db, "phase": "focus",
             "remainingSeconds": 900, "sessionNumber": 1, "completedFocusSessions": 0},
            {"op": "save_checkpoint", "path": self.db, "phase": "shortBreak",
             "remainingSeconds": 120, "sessionNumber": 3, "completedFocusSessions": 3},
        ])

        conn = sqlite3.connect(self.db)
        try:
            rows = conn.execute(
                "SELECT phase, remaining_seconds, session_number, completed_focus_sessions "
                "FROM checkpoint").fetchall()
        finally:
            conn.close()
        self.assertEqual(rows, [("shortBreak", 120, 3, 3)])

    def test_months_old_checkpoint_still_loads(self):
        self.init()
        old = 1730000000123  # months before any plausible policy TTL
        conn = sqlite3.connect(self.db)
        try:
            conn.execute(
                "INSERT INTO checkpoint (singleton, phase, remaining_seconds, "
                "session_number, completed_focus_sessions, saved_at) "
                "VALUES (1, 'focus', 612, 3, 2, ?)", (old,))
            conn.commit()
        finally:
            conn.close()

        loaded = run_helper([{"op": "load_checkpoint", "path": self.db}])[0]
        self.assertEqual(loaded["checkpoint"], {
            "phase": "focus", "remainingSeconds": 612,
            "sessionNumber": 3, "completedFocusSessions": 2, "savedAt": old,
        })

    def test_clear_checkpoint_removes_the_row(self):
        self.init()
        save = {
            "op": "save_checkpoint", "path": self.db, "phase": "focus",
            "remainingSeconds": 900, "sessionNumber": 1, "completedFocusSessions": 0,
        }
        responses = run_helper([save, {"op": "clear_checkpoint", "path": self.db},
                                {"op": "load_checkpoint", "path": self.db}])

        self.assertTrue(responses[1]["ok"])
        self.assertIsNone(responses[2]["checkpoint"])
        conn = sqlite3.connect(self.db)
        try:
            count = conn.execute("SELECT COUNT(*) FROM checkpoint").fetchone()[0]
        finally:
            conn.close()
        self.assertEqual(count, 0)

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

    def test_corrupt_database_degrades_to_noop_and_helper_survives(self):
        self.init()
        # Corrupt the published artifact directly with non-SQLite bytes.
        with open(self.db, "wb") as handle:
            handle.write(b"not a sqlite database\n")
        fresh = os.path.join(self.tmp.name, "fresh", "focus-log.sqlite3")
        responses = run_helper([
            {"op": "record_focus", "path": self.db,
             "id": "zc-corrupt-f1", "durationMinutes": 25, "timestamp": 1730000000123},
            {"op": "status", "path": fresh},
        ])

        failed = responses[0]
        self.assertFalse(failed["ok"])
        self.assertEqual(failed["status"], "degraded")
        self.assertTrue(failed["error"])
        # A later, healthy command still works: one failure never kills the helper.
        self.assertTrue(responses[1]["ok"], "helper must survive a storage failure")
        self.assertEqual(responses[1]["counts"], {"focus": 0, "cycle": 0, "countdown": 0})

    def test_unwritable_database_directory_degrades_without_crashing(self):
        # A regular file where the database directory should be makes every
        # filesystem operation on the parent fail.
        blocker = os.path.join(self.tmp.name, "blocked")
        with open(blocker, "w") as handle:
            handle.write("x")
        blocked_db = os.path.join(blocker, "focus-log.sqlite3")
        responses = run_helper([
            {"op": "init", "path": blocked_db},
            {"op": "status", "path": self.db},
        ])

        self.assertFalse(responses[0]["ok"])
        self.assertEqual(responses[0]["status"], "degraded")
        self.assertTrue(responses[0]["error"])
        self.assertTrue(responses[1]["ok"], "helper must survive an unwritable path")

    def test_prune_removes_only_old_records_and_keeps_the_checkpoint(self):
        """Manual prune deletes only records past record_retention_days.

        A months-old checkpoint must survive: a paused Focus Session stays
        resumable (focus-log-schema.md, ADR 0003).
        """
        self.init()
        now_s = int(time.time())
        retention_days = 30
        old_ms = (now_s - 40 * 86400) * 1000
        fresh_ms = (now_s - 1 * 86400) * 1000
        checkpoint_ms = (now_s - 400 * 86400) * 1000

        # Seed the published artifact directly: one old and one fresh record
        # of each kind, plus a checkpoint older than any retention value.
        conn = sqlite3.connect(self.db)
        try:
            with conn:
                conn.execute(
                    "UPDATE focus_log_policy SET value = ? WHERE key = 'record_retention_days'",
                    (retention_days,))
                conn.execute(
                    "INSERT INTO focus_record (id, duration_minutes, recorded_at) "
                    "VALUES (?, ?, ?), (?, ?, ?)",
                    ("old-focus", 25, old_ms, "fresh-focus", 25, fresh_ms))
                conn.execute(
                    "INSERT INTO cycle_record (id, recorded_at) VALUES (?, ?), (?, ?)",
                    ("old-cycle", old_ms, "fresh-cycle", fresh_ms))
                conn.execute(
                    "INSERT INTO countdown_record (id, duration_minutes, recorded_at) "
                    "VALUES (?, ?, ?), (?, ?, ?)",
                    ("old-countdown", 5, old_ms, "fresh-countdown", 5, fresh_ms))
                conn.execute(
                    "INSERT INTO checkpoint (singleton, phase, remaining_seconds, "
                    "session_number, completed_focus_sessions, saved_at) "
                    "VALUES (1, 'focus', 600, 2, 1, ?)",
                    (checkpoint_ms,))
        finally:
            conn.close()

        response = run_helper([{"op": "prune", "path": self.db}])[0]
        self.assertTrue(response["ok"], response)
        self.assertEqual(response["op"], "prune")

        conn = sqlite3.connect(self.db)
        try:
            for table, kind in (("focus_record", "focus"), ("cycle_record", "cycle"),
                                ("countdown_record", "countdown")):
                ids = [row[0] for row in conn.execute("SELECT id FROM " + table)]
                self.assertEqual(ids, ["fresh-" + kind], table)
            self.assertEqual(
                conn.execute("SELECT saved_at FROM checkpoint").fetchall(),
                [(checkpoint_ms,)])
            policy = dict(conn.execute(
                "SELECT key, value FROM focus_log_policy").fetchall())
            self.assertEqual(policy["record_retention_days"], retention_days)
            self.assertEqual(policy["checkpoint_ttl_days"], 0)
        finally:
            conn.close()

    def test_prune_with_default_keep_forever_policy_deletes_nothing(self):
        """Both policy values default to 0 (keep forever); prune is a no-op."""
        self.init()
        ancient_ms = 1_000_000_000_000  # 2001 — older than any real retention
        conn = sqlite3.connect(self.db)
        try:
            with conn:
                conn.execute(
                    "INSERT INTO focus_record (id, duration_minutes, recorded_at) "
                    "VALUES ('ancient-focus', 25, ?)", (ancient_ms,))
        finally:
            conn.close()

        response = run_helper([{"op": "prune", "path": self.db}])[0]
        self.assertTrue(response["ok"], response)
        self.assertEqual(response["deleted"], {
            "focus_record": 0, "cycle_record": 0, "countdown_record": 0})

        conn = sqlite3.connect(self.db)
        try:
            ids = conn.execute("SELECT id FROM focus_record").fetchall()
            policy = dict(conn.execute(
                "SELECT key, value FROM focus_log_policy").fetchall())
        finally:
            conn.close()
        self.assertEqual(ids, [("ancient-focus",)])
        self.assertEqual(policy, {"checkpoint_ttl_days": 0,
                                  "record_retention_days": 0})

    def test_failed_command_reports_degraded_status_with_a_reason(self):
        # A missing path stands in for a helper that cannot open storage at all.
        response = run_helper([{"op": "status"}])[0]
        self.assertEqual(response["status"], "degraded")
        self.assertTrue(response["error"])
    def test_cycle_record_persists_id_and_timestamp(self):
        self.init()
        event = {"op": "record_cycle", "path": self.db,
                 "id": "zc-test-c1", "timestamp": 1730451600000}
        response = run_helper([event])[0]

        self.assertTrue(response["ok"], response)
        self.assertEqual(response["inserted"], 1)
        conn = sqlite3.connect(self.db)
        try:
            rows = conn.execute(
                "SELECT id, recorded_at FROM cycle_record").fetchall()
        finally:
            conn.close()
        self.assertEqual(rows, [("zc-test-c1", 1730451600000)])

    def test_cycle_redelivery_is_idempotent(self):
        self.init()
        event = {"op": "record_cycle", "path": self.db,
                 "id": "zc-test-c1", "timestamp": 1730451600000}
        responses = run_helper([event, event])

        self.assertEqual([r["inserted"] for r in responses], [1, 0])
        conn = sqlite3.connect(self.db)
        try:
            count = conn.execute("SELECT COUNT(*) FROM cycle_record").fetchone()[0]
        finally:
            conn.close()
        self.assertEqual(count, 1)

    def test_countdown_record_uses_deterministic_synthesized_id(self):
        self.init()
        event = {"op": "record_countdown", "path": self.db,
                 "durationMinutes": 5, "timestamp": 1730451600000}
        response = run_helper([event])[0]

        self.assertTrue(response["ok"], response)
        self.assertEqual(response["inserted"], 1)
        conn = sqlite3.connect(self.db)
        try:
            rows = conn.execute(
                "SELECT id, duration_minutes, recorded_at FROM countdown_record"
            ).fetchall()
        finally:
            conn.close()
        self.assertEqual(rows, [("zc-cd-1730451600000-5", 5, 1730451600000)])

    def test_countdown_redelivery_is_idempotent(self):
        self.init()
        event = {"op": "record_countdown", "path": self.db,
                 "durationMinutes": 5, "timestamp": 1730451600000}
        responses = run_helper([event, event])

        self.assertEqual([r["inserted"] for r in responses], [1, 0])
        conn = sqlite3.connect(self.db)
        try:
            rows = conn.execute(
                "SELECT id, duration_minutes, recorded_at FROM countdown_record"
            ).fetchall()
        finally:
            conn.close()
        self.assertEqual(rows, [("zc-cd-1730451600000-5", 5, 1730451600000)])

    def test_distinct_countdowns_get_distinct_synthesized_ids(self):
        self.init()
        run_helper([
            {"op": "record_countdown", "path": self.db,
             "durationMinutes": 5, "timestamp": 1730451600000},
            {"op": "record_countdown", "path": self.db,
             "durationMinutes": 5, "timestamp": 1730473200000},
        ])
        conn = sqlite3.connect(self.db)
        try:
            ids = [row[0] for row in conn.execute(
                "SELECT id FROM countdown_record ORDER BY id")]
        finally:
            conn.close()
        self.assertEqual(ids, ["zc-cd-1730451600000-5", "zc-cd-1730473200000-5"])

    def test_countdowns_do_not_inflate_canonical_focus_metric(self):
        self.init()
        run_helper([
            {"op": "record_focus", "path": self.db, "id": "zc-test-f1",
             "durationMinutes": 25, "timestamp": 1730451600000},
            {"op": "record_countdown", "path": self.db,
             "durationMinutes": 5, "timestamp": 1730451600000},
        ])
        conn = sqlite3.connect(self.db)
        try:
            # Verbatim from docs/focus-log-schema.md, "Canonical metric".
            minutes = conn.execute(
                "SELECT SUM(duration_minutes) AS focus_minutes FROM focus_record"
            ).fetchone()[0]
        finally:
            conn.close()
        self.assertEqual(minutes, 25)

    def test_documented_dashboard_queries_return_documented_results(self):
        self.init()
        today_ms = int(time.time() * 1000)
        today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
        run_helper([
            {"op": "record_focus", "path": self.db, "id": "zc-test-f1",
             "durationMinutes": 25, "timestamp": 1730451600000},
            {"op": "record_focus", "path": self.db, "id": "zc-test-f2",
             "durationMinutes": 50, "timestamp": 1730473200000},
            {"op": "record_focus", "path": self.db, "id": "zc-test-f3",
             "durationMinutes": 25, "timestamp": 1730556000000},
            {"op": "record_focus", "path": self.db, "id": "zc-test-f4",
             "durationMinutes": 50, "timestamp": today_ms},
            {"op": "record_cycle", "path": self.db, "id": "zc-test-c1",
             "timestamp": 1730451600000},
            {"op": "record_cycle", "path": self.db, "id": "zc-test-c2",
             "timestamp": 1730556000000},
        ])

        conn = sqlite3.connect(self.db)
        try:
            # The four example queries, verbatim from the published schema.
            daily = conn.execute("""
                SELECT date(recorded_at / 1000, 'unixepoch', 'localtime') AS day,
                       SUM(duration_minutes) AS minutes,
                       COUNT(*) AS sessions
                FROM focus_record
                GROUP BY day ORDER BY day;
            """).fetchall()
            todays = conn.execute("""
                SELECT COALESCE(SUM(duration_minutes), 0) AS minutes
                FROM focus_record
                WHERE date(recorded_at / 1000, 'unixepoch', 'localtime') = date('now','localtime');
            """).fetchone()[0]
            cycles = conn.execute("SELECT COUNT(*) FROM cycle_record;").fetchone()[0]
            longest = conn.execute("""
                SELECT day, minutes FROM (
                  SELECT date(recorded_at / 1000, 'unixepoch', 'localtime') AS day,
                         SUM(duration_minutes) AS minutes
                  FROM focus_record GROUP BY day
                ) ORDER BY minutes DESC LIMIT 1;
            """).fetchone()
        finally:
            conn.close()

        self.assertEqual(daily, [
            ("2024-11-01", 75, 2),
            ("2024-11-02", 25, 1),
            (today, 50, 1),
        ])
        self.assertEqual(todays, 50)
        self.assertEqual(cycles, 2)
        self.assertEqual(longest, ("2024-11-01", 75))


if __name__ == "__main__":
    unittest.main()

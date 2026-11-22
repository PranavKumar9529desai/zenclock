#!/usr/bin/env bash
# Focus Log smoke test: drive a Focus Session completion through the existing
# IPC + service debug seam, then assert against the published SQLite artifact.
# Run on the live Omarchy desktop: ./tests/focus-log.sh
set -uo pipefail

source "$(dirname "$0")/adapter.sh"

failures=0
check() { "$@" || failures=$((failures + 1)); }
eq() { zc_assert_eq "$@"; }

cleanup() { zc_hide >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Read the artifact with an ordinary SQLite client, never through plugin IPC.
zfl_sql() {
  python3 - "$ZFL_DB" "$1" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
try:
    for row in conn.execute(sys.argv[2]):
        print("\t".join("" if value is None else str(value) for value in row))
finally:
    conn.close()
PY
}

# Baseline: the Focus Log may already hold records from earlier runs, so every
# assertion is a delta. The file is never deleted or edited by this test.
zc_hide >/dev/null
check zc_wait_field '.serviceReady' true 10
zc_call debugResetAll '' >/dev/null
zc_call debugSetEventCapture true >/dev/null
sleep 0.4

check zc_has_field focusLog
baseline="$(zc_field '.focusLog.counts.focus')"
eq "focus count is a number" "$([[ "$baseline" =~ ^[0-9]+$ ]] && echo yes || echo no)" "yes"
check zc_wait_field '.focusLog.status' ok 10

ZFL_DB="$(zc_field '.focusLog.path')"
check eq "Focus Log path is reported" \
  "$([[ -n "$ZFL_DB" && "$ZFL_DB" == *zenclock/focus-log.sqlite3 ]] && echo set || echo empty)" "set"
check eq "Focus Log file exists at the documented state path" \
  "$([[ -f "$ZFL_DB" ]] && echo yes || echo no)" "yes"
check eq "schema version is reported" "$(zc_field '.focusLog.schemaVersion')" "1"
check eq "WAL mode is reported" "$(zc_field '.focusLog.journalMode')" "wal"

# Drive the existing deadline machine. debugResetAll preserves the phase, so
# advance through any break until a Focus Session actually completes.
for attempt in 1 2 3 4 5 6 7 8; do
  zc_call debugAdvancePhase '' >/dev/null
  if zc_wait_field '.focusLog.counts.focus' "$((baseline + 1))" 5 >/dev/null 2>&1; then
    break
  fi
done
check zc_wait_field '.focusLog.counts.focus' "$((baseline + 1))" 15

focus_event="$(zc_events | jq -c 'map(select(.type == "focusSessionCompleted")) | .[0]')"
check eq "focus completion event carries a session ID" \
  "$(jq -r '.sessionId | type' <<<"$focus_event")" "string"
session_id="$(jq -r '.sessionId' <<<"$focus_event")"
duration="$(jq -r '.durationMinutes' <<<"$focus_event")"
timestamp="$(jq -r '.timestamp' <<<"$focus_event")"

# Assert directly against the file — this is the artifact users consume.
check eq "journal mode in the file is WAL" "$(zfl_sql 'PRAGMA journal_mode')" "wal"
check eq "schema version in the file is 1" \
  "$(zfl_sql 'SELECT version FROM schema_version')" "1"
check eq "exactly one new Focus Record was written" \
  "$(zfl_sql 'SELECT COUNT(*) FROM focus_record')" "$((baseline + 1))"
check eq "Focus Record holds the Focus Session ID" \
  "$(zfl_sql "SELECT id FROM focus_record WHERE id = '$session_id'")" "$session_id"
check eq "Focus Record holds the configured duration" \
  "$(zfl_sql "SELECT duration_minutes FROM focus_record WHERE id = '$session_id'")" "$duration"
check eq "Focus Record holds the completion timestamp" \
  "$(zfl_sql "SELECT recorded_at FROM focus_record WHERE id = '$session_id'")" "$timestamp"
check eq "completion timestamp is Unix epoch milliseconds" \
  "$([[ "$timestamp" =~ ^[0-9]{13}$ ]] && echo yes || echo no)" "yes"
# Redeliver the same completion through the seam; it must not double-count.
zc_call debugRedeliverFocus "$focus_event" >/dev/null
sleep 0.6
check eq "redelivery leaves one Focus Record" \
  "$(zfl_sql 'SELECT COUNT(*) FROM focus_record')" "$((baseline + 1))"
check eq "state count is unchanged by redelivery" \
  "$(zc_field '.focusLog.counts.focus')" "$((baseline + 1))"
check eq "storage status stays ok" "$(zc_field '.focusLog.status')" "ok"

zc_call debugSetEventCapture false >/dev/null
zc_call debugResetAll '' >/dev/null

if (( failures > 0 )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All Focus Log smoke checks passed"

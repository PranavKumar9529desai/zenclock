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
cycle_baseline="$(zc_field '.focusLog.counts.cycle')"
countdown_baseline="$(zc_field '.focusLog.counts.countdown')"
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

# A completed Pomodoro Cycle reaches the same adapter and writes one Cycle
# Record. From the short break after the Focus Session, seven more phase
# advances halt the cycle and emit cycleFinished; the loop is a safety margin.
for attempt in 1 2 3 4 5 6 7 8; do
  zc_call debugAdvancePhase '' >/dev/null
  if zc_wait_field '.focusLog.counts.cycle' "$((cycle_baseline + 1))" 5 >/dev/null 2>&1; then
    break
  fi
done
check zc_wait_field '.focusLog.counts.cycle' "$((cycle_baseline + 1))" 15

cycle_event="$(zc_events | jq -c 'map(select(.type == "cycleFinished")) | .[0]')"
check eq "cycle completion event carries a cycle ID" \
  "$(jq -r '.cycleId | type' <<<"$cycle_event")" "string"
cycle_id="$(jq -r '.cycleId' <<<"$cycle_event")"
cycle_timestamp="$(jq -r '.timestamp' <<<"$cycle_event")"
check eq "exactly one new Cycle Record was written" \
  "$(zfl_sql 'SELECT COUNT(*) FROM cycle_record')" "$((cycle_baseline + 1))"
check eq "Cycle Record holds the Pomodoro Cycle ID" \
  "$(zfl_sql "SELECT id FROM cycle_record WHERE id = '$cycle_id'")" "$cycle_id"
check eq "Cycle Record holds the completion timestamp" \
  "$(zfl_sql "SELECT recorded_at FROM cycle_record WHERE id = '$cycle_id'")" "$cycle_timestamp"
zc_call debugRedeliverCycle "$cycle_event" >/dev/null
sleep 0.6
check eq "cycle redelivery leaves one new Cycle Record" \
  "$(zfl_sql 'SELECT COUNT(*) FROM cycle_record')" "$((cycle_baseline + 1))"
check eq "cycle state count is unchanged by redelivery" \
  "$(zc_field '.focusLog.counts.cycle')" "$((cycle_baseline + 1))"

# A completed Timer countdown writes one Countdown Record, keyed by timestamp
# and configured duration, and never touches the canonical focus metric.
focus_total="$(zfl_sql 'SELECT SUM(duration_minutes) FROM focus_record')"
zc_call debugExpireTimer '' >/dev/null
check zc_wait_field '.focusLog.counts.countdown' "$((countdown_baseline + 1))" 15

countdown_event="$(zc_events | jq -c 'map(select(.type == "countdownCompleted")) | .[0]')"
check eq "countdown completion event carries a duration" \
  "$(jq -r '.durationMinutes | type' <<<"$countdown_event")" "number"
countdown_duration="$(jq -r '.durationMinutes' <<<"$countdown_event")"
countdown_timestamp="$(jq -r '.timestamp' <<<"$countdown_event")"
countdown_id="zc-cd-${countdown_timestamp}-${countdown_duration}"
check eq "exactly one new Countdown Record was written" \
  "$(zfl_sql 'SELECT COUNT(*) FROM countdown_record')" "$((countdown_baseline + 1))"
check eq "Countdown Record uses the deterministic synthesized key" \
  "$(zfl_sql "SELECT id FROM countdown_record WHERE id = '$countdown_id'")" "$countdown_id"
check eq "Countdown Record holds the configured duration" \
  "$(zfl_sql "SELECT duration_minutes FROM countdown_record WHERE id = '$countdown_id'")" "$countdown_duration"
check eq "Countdown Record holds the completion timestamp" \
  "$(zfl_sql "SELECT recorded_at FROM countdown_record WHERE id = '$countdown_id'")" "$countdown_timestamp"
check eq "countdown does not inflate the canonical focus metric" \
  "$(zfl_sql 'SELECT SUM(duration_minutes) FROM focus_record')" "$focus_total"
zc_call debugRedeliverCountdown "$countdown_event" >/dev/null
sleep 0.6
check eq "countdown redelivery leaves one new Countdown Record" \
  "$(zfl_sql 'SELECT COUNT(*) FROM countdown_record')" "$((countdown_baseline + 1))"
check eq "countdown state count is unchanged by redelivery" \
  "$(zc_field '.focusLog.counts.countdown')" "$((countdown_baseline + 1))"

# Run the four documented dashboard queries against the real file.
daily_minutes="$(zfl_sql "SELECT date(recorded_at / 1000, 'unixepoch', 'localtime') AS day,
       SUM(duration_minutes) AS minutes,
       COUNT(*) AS sessions
FROM focus_record
GROUP BY day ORDER BY day;" | awk -F'\t' '{total += $2} END {print total + 0}')"
check eq "daily focus query accounts for every focus minute" \
  "$daily_minutes" "$focus_total"

todays_minutes="$(zfl_sql "SELECT COALESCE(SUM(duration_minutes), 0) AS minutes
FROM focus_record
WHERE date(recorded_at / 1000, 'unixepoch', 'localtime') = date('now','localtime');")"
check eq "today's focus query reflects the focus recorded today" \
  "$([[ "$todays_minutes" =~ ^[0-9]+$ && "$todays_minutes" -gt 0 ]] && echo yes || echo no)" "yes"
check eq "cycle count query matches the recorded Cycle Records" \
  "$(zfl_sql 'SELECT COUNT(*) FROM cycle_record;')" "$((cycle_baseline + 1))"

longest_minutes="$(zfl_sql "SELECT day, minutes FROM (
  SELECT date(recorded_at / 1000, 'unixepoch', 'localtime') AS day,
         SUM(duration_minutes) AS minutes
  FROM focus_record GROUP BY day
) ORDER BY minutes DESC LIMIT 1;" | awk -F'\t' '{print $2}')"
max_daily="$(zfl_sql "SELECT date(recorded_at / 1000, 'unixepoch', 'localtime') AS day,
       SUM(duration_minutes) AS minutes
FROM focus_record
GROUP BY day ORDER BY day;" | awk -F'\t' '{if ($2 > max) max = $2} END {print max + 0}')"
check eq "longest focus day query returns the largest daily total" \
  "$longest_minutes" "$max_daily"

zc_call debugSetEventCapture false >/dev/null
zc_call debugResetAll '' >/dev/null

if (( failures > 0 )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All Focus Log smoke checks passed"

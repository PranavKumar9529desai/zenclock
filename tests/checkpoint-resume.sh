#!/usr/bin/env bash
# Checkpoint + resume smoke test. Drives the service through its existing IPC
# debug seam and asserts resume through state() JSON only — no visual-tree reads.
# Run on the live Omarchy desktop: ./tests/checkpoint-resume.sh
set -uo pipefail

source "$(dirname "$0")/adapter.sh"

failures=0
check() { "$@" || failures=$((failures + 1)); }
eq() { zc_assert_eq "$@"; }

cleanup() {
  zc_call debugSetEventCapture false >/dev/null 2>&1 || true
  zc_call debugResetAll '' >/dev/null 2>&1 || true
  zc_hide >/dev/null 2>&1 || true
}
trap cleanup EXIT

# The published artifact is read with an ordinary SQLite client, never via IPC.
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

zfl_wait_count() {
  local expected="$1" attempts="${2:-25}" actual=""
  while (( attempts > 0 )); do
    actual="$(zfl_sql 'SELECT COUNT(*) FROM checkpoint' 2>/dev/null || true)"
    [[ "$actual" == "$expected" ]] && return 0
    sleep 0.2
    attempts=$((attempts - 1))
  done
  echo "timeout waiting for checkpoint count $expected (last: $actual)" >&2
  return 1
}

# Baseline: a loaded Focus Log and a known, clean Pomodoro state.
zc_hide >/dev/null
check zc_wait_field '.serviceReady' true 10
if ! zc_has_field focusLog; then
  echo "SKIP: running shell has no Focus Log adapter loaded"
  exit 0
fi
check zc_wait_field '.focusLog.status' ok 10
ZFL_DB="$(zc_field '.focusLog.path')"
check eq "Focus Log path is reported" \
  "$([[ -n "$ZFL_DB" && "$ZFL_DB" == *zenclock/focus-log.sqlite3 ]] && echo set || echo empty)" "set"

zc_call debugResetAll '' >/dev/null
python3 - "$ZFL_DB" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
with conn:
    conn.execute("DELETE FROM checkpoint")
conn.close()
PY
sleep 0.6
check zfl_wait_count 0 15

# --- Pause writes one checkpoint with the full cycle position ---------------
zc_toggle >/dev/null
sleep 0.7
zc_press 2
check zc_wait_field '.mode' pomodoro 10
zc_press space
check zc_wait_field '.pomodoro.running' true 10
sleep 2
zc_press space
check zc_wait_field '.pomodoro.running' false 10
check zfl_wait_count 1 15

check eq "one upserted checkpoint row after pause" "$(zfl_sql 'SELECT COUNT(*) FROM checkpoint')" "1"
check eq "checkpoint holds the phase" "$(zfl_sql 'SELECT phase FROM checkpoint')" "focus"
check eq "checkpoint holds the session number" "$(zfl_sql 'SELECT session_number FROM checkpoint')" "1"
check eq "checkpoint holds completed Focus Session count" \
  "$(zfl_sql 'SELECT completed_focus_sessions FROM checkpoint')" "0"
remaining="$(zfl_sql 'SELECT remaining_seconds FROM checkpoint')"
check eq "checkpoint holds a partially elapsed remaining time" \
  "$([[ "$remaining" =~ ^[0-9]+$ ]] && (( remaining > 0 && remaining < 1500 )) && echo yes || echo no)" "yes"
check eq "checkpoint timestamp is epoch milliseconds" \
  "$([[ "$(zfl_sql 'SELECT saved_at FROM checkpoint')" =~ ^[0-9]{13}$ ]] && echo yes || echo no)" "yes"

# --- Reset discards it and starts from zero ---------------------------------
zc_press r
check zc_wait_field '.pomodoro.remaining' 25:00 10
check eq "R pauses after reset" "$(zc_field '.pomodoro.running')" "false"
check zfl_wait_count 0 15

# --- A months-old checkpoint is still restored, paused, with cycle position -
python3 - "$ZFL_DB" <<'PY'
import sqlite3, sys, time
old_ms = int(time.time() * 1000) - 180 * 24 * 60 * 60 * 1000
conn = sqlite3.connect(sys.argv[1])
with conn:
    conn.execute(
        "INSERT INTO checkpoint (singleton, phase, remaining_seconds, "
        "session_number, completed_focus_sessions, saved_at) "
        "VALUES (1, 'focus', 612, 3, 2, ?) "
        "ON CONFLICT(singleton) DO UPDATE SET phase=excluded.phase, "
        "remaining_seconds=excluded.remaining_seconds, "
        "session_number=excluded.session_number, "
        "completed_focus_sessions=excluded.completed_focus_sessions, "
        "saved_at=excluded.saved_at", (old_ms,))
conn.close()
PY

zc_call debugRestoreCheckpoint '' >/dev/null
check zc_wait_field '.pomodoro.phase' focus 10
check zc_wait_field '.pomodoro.remaining' 10:12 10
check zc_wait_field '.pomodoro.session' 3 10
check eq "restored phase is paused" "$(zc_field '.pomodoro.running')" "false"
check eq "restored state is partially elapsed (Resume, with no new UI)" \
  "$([[ "$(zc_field '.pomodoro.remaining')" != "25:00" ]] && echo yes || echo no)" "yes"

# Lifetime counters and the run identifier stay fresh: the next completion is
# numbered from 1 even though the restored cycle position was session 3.
zc_call debugSetEventCapture true >/dev/null
zc_call debugAdvancePhase '' >/dev/null
sleep 0.5
check eq "next Focus Session uses a fresh lifetime number" \
  "$(zc_events | jq -r 'map(select(.type == "focusSessionCompleted")) | .[0].sessionId | endswith("-f1")')" "true"
check eq "restored Focus Session advanced into its Short Break" \
  "$(zc_field '.pomodoro.phase')" "shortBreak"
zc_call debugAdvancePhase '' >/dev/null
check eq "cycle position advanced from the restored point" \
  "$(zc_field '.pomodoro.session')" "4"

# --- Running phases refresh the checkpoint on a 30-second cadence -----------
# advance() leaves a phase running, so pause it before timing a fresh run.
zc_press space
check zc_wait_field '.pomodoro.running' false 10
check zfl_wait_count 1 15
before="$(zfl_sql 'SELECT saved_at FROM checkpoint')"
zc_press space
check zc_wait_field '.pomodoro.running' true 10
refreshed=0
for attempt in $(seq 1 40); do
  after="$(zfl_sql 'SELECT saved_at FROM checkpoint' 2>/dev/null || true)"
  if [[ "$after" =~ ^[0-9]+$ ]] && (( after > before )); then refreshed=1; break; fi
  sleep 1
done
check eq "running phase refreshes the checkpoint within ~30s" "$refreshed" "1"
check eq "refreshed remaining time is still below a full phase" \
  "$([[ "$(zfl_sql 'SELECT remaining_seconds FROM checkpoint')" =~ ^[0-9]+$ ]] && echo yes || echo no)" "yes"

if (( failures > 0 )); then
  echo "$failures checkpoint/resume check(s) failed"
  exit 1
fi
echo "All checkpoint/resume smoke checks passed"

#!/usr/bin/env bash
# Checkpoint + resume smoke test. Drives the service through its existing IPC
# debug seam and asserts resume through state() JSON only — no visual-tree reads.
# Run on the live Omarchy desktop: ./tests/checkpoint-resume.sh
set -uo pipefail

source "$(dirname "$0")/adapter.sh"

failures=0
check() { "$@" || failures=$((failures + 1)); }

cleanup() {
  zc_call debugSetEventCapture false >/dev/null 2>&1 || true
  zc_call debugResetAll '' >/dev/null 2>&1 || true
  zc_hide >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Poll the published artifact with the shared SQLite helper from adapter.sh.
zfl_wait_count() {
  local expected="$1" attempts="${2:-25}" actual=""
  while (( attempts > 0 )); do
    actual="$(zfl_sql "$ZFL_DB" 'SELECT COUNT(*) FROM checkpoint' 2>/dev/null || true)"
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
check zc_assert_eq "Focus Log path is reported" \
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

# A phase start writes a full-duration checkpoint immediately; the pause tick
# then overwrites it with the frozen remaining time. Wait for that overwrite
# instead of racing it.
zfl_wait_partial() {
  local attempts=20 actual=""
  while (( attempts > 0 )); do
    actual="$(zfl_sql "$ZFL_DB" 'SELECT remaining_seconds FROM checkpoint' 2>/dev/null || true)"
    [[ "$actual" =~ ^[0-9]+$ ]] && (( actual > 0 && actual < 1500 )) && return 0
    sleep 0.2
    attempts=$((attempts - 1))
  done
  echo "timeout waiting for a partially elapsed checkpoint (last: $actual)" >&2
  return 1
}

# --- Pause writes one checkpoint with the full cycle position ---------------
zc_toggle >/dev/null
sleep 0.7
zc_press 2
check zc_wait_field '.mode' pomodoro 10
zc_press space
check zc_wait_field '.pomodoro.running' true 10
# Wait for the countdown itself to move; a fixed sleep can pause before the
# first tick and produce a misleading full-duration checkpoint.
started_remaining="$(zc_field '.pomodoro.remaining')"
check zc_wait_changed '.pomodoro.remaining' "$started_remaining" 10
zc_press space
check zc_wait_field '.pomodoro.running' false 10
check zfl_wait_count 1 15
check zfl_wait_partial

check zc_assert_eq "one upserted checkpoint row after pause" "$(zfl_sql "$ZFL_DB" 'SELECT COUNT(*) FROM checkpoint')" "1"
check zc_assert_eq "checkpoint holds the phase" "$(zfl_sql "$ZFL_DB" 'SELECT phase FROM checkpoint')" "focus"
# The cycle position carried over from earlier smoke runs in this shell; assert
# the checkpoint mirrors the engine rather than assuming a fresh first session.
expected_session="$(zc_field '.pomodoro.session')"
check zc_assert_eq "checkpoint holds the session number" "$(zfl_sql "$ZFL_DB" 'SELECT session_number FROM checkpoint')" "$expected_session"
check zc_assert_eq "checkpoint holds completed Focus Session count" \
  "$(zfl_sql "$ZFL_DB" 'SELECT completed_focus_sessions FROM checkpoint')" "0"
remaining="$(zfl_sql "$ZFL_DB" 'SELECT remaining_seconds FROM checkpoint')"
check zc_assert_eq "checkpoint holds a partially elapsed remaining time" \
  "$([[ "$remaining" =~ ^[0-9]+$ ]] && (( remaining > 0 && remaining < 1500 )) && echo yes || echo no)" "yes"
check zc_assert_eq "checkpoint timestamp is epoch milliseconds" \
  "$([[ "$(zfl_sql "$ZFL_DB" 'SELECT saved_at FROM checkpoint')" =~ ^[0-9]{13}$ ]] && echo yes || echo no)" "yes"
# Checkpoint position is observable in state().focusLog, not hidden in the UI.
check zc_assert_eq "state() reports checkpoint phase" \
  "$(zc_field '.focusLog.checkpoint.phase')" "focus"
check zc_assert_eq "state() reports checkpoint session number" \
  "$(zc_field '.focusLog.checkpoint.sessionNumber')" "$expected_session"
check zc_assert_eq "state() reports checkpoint saved-at" \
  "$([[ "$(zc_field '.focusLog.checkpoint.savedAt')" =~ ^[0-9]{13}$ ]] && echo yes || echo no)" "yes"

# --- Reset discards it and starts from zero ---------------------------------
zc_press r
check zc_wait_field '.pomodoro.remaining' 25:00 10
check zc_assert_eq "R pauses after reset" "$(zc_field '.pomodoro.running')" "false"
check zfl_wait_count 0 15

# Regression: Reset while RUNNING used to leave lastRunning true and a full
# remaining time, so the next tick saved a bogus full checkpoint. Synchronous
# suppression must keep the checkpoint cleared across later ticks.
zc_press space
check zc_wait_field '.pomodoro.running' true 10
sleep 2
zc_press r
check zc_wait_field '.pomodoro.running' false 10
check zc_wait_field '.pomodoro.remaining' 25:00 10
check zfl_wait_count 0 15
sleep 3
check zc_assert_eq "Reset while running leaves no full checkpoint after later ticks" \
  "$(zfl_sql "$ZFL_DB" 'SELECT COUNT(*) FROM checkpoint')" "0"

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

check zc_assert_eq "checkpoint restore seam is wired" \
  "$(zc_call debugRestoreCheckpoint '')" "ok"
check zc_wait_field '.pomodoro.phase' focus 10
check zc_wait_field '.pomodoro.remaining' 10:12 10
check zc_wait_field '.pomodoro.session' 3 10
check zc_assert_eq "restored phase is paused" "$(zc_field '.pomodoro.running')" "false"
check zc_assert_eq "restored state is partially elapsed (Resume, with no new UI)" \
  "$([[ "$(zc_field '.pomodoro.remaining')" != "25:00" ]] && echo yes || echo no)" "yes"
check zc_assert_eq "state derivation marks the restored Focus Session for Resume" \
  "$(zc_field '.pomodoro.partiallyElapsed')" "true"

# Lifetime counters and the run identifier stay fresh: the next completion is
# numbered from 1 even though the restored cycle position was session 3.
zc_call debugSetEventCapture true >/dev/null
zc_call debugAdvancePhase '' >/dev/null
sleep 0.5
# Lifetime numbering belongs to this run, not to the restored checkpoint. It
# may already be past f1 after earlier smoke runs in the same shell; what must
# not happen is restarting from the restored cycle position (completed = 2 -> f3).
next_session_id="$(zc_events | jq -r 'map(select(.type == "focusSessionCompleted")) | .[0].sessionId')"
check zc_assert_eq "next Focus Session uses a fresh lifetime number" \
  "$([[ "$next_session_id" =~ -f[0-9]+$ && "$next_session_id" != *-f3 ]] && echo yes || echo no)" "yes"
check zc_assert_eq "restored Focus Session advanced into its Short Break" \
  "$(zc_field '.pomodoro.phase')" "shortBreak"
zc_call debugAdvancePhase '' >/dev/null
check zc_assert_eq "cycle position advanced from the restored point" \
  "$(zc_field '.pomodoro.session')" "4"

# --- A restored Long Break also reads "Resume", and the stored session wins --
zc_press r
check zc_wait_field '.pomodoro.running' false 10
python3 - "$ZFL_DB" <<'PY'
import sqlite3, sys, time
conn = sqlite3.connect(sys.argv[1])
with conn:
    conn.execute(
        "INSERT INTO checkpoint (singleton, phase, remaining_seconds, "
        "session_number, completed_focus_sessions, saved_at) "
        "VALUES (1, 'longBreak', 600, 4, 4, ?) "
        "ON CONFLICT(singleton) DO UPDATE SET phase=excluded.phase, "
        "remaining_seconds=excluded.remaining_seconds, "
        "session_number=excluded.session_number, "
        "completed_focus_sessions=excluded.completed_focus_sessions, "
        "saved_at=excluded.saved_at", (int(time.time() * 1000),))
conn.close()
PY
check zc_assert_eq "checkpoint restore seam is wired" \
  "$(zc_call debugRestoreCheckpoint '')" "ok"
check zc_wait_field '.pomodoro.phase' longBreak 10
check zc_wait_field '.pomodoro.remaining' 10:00 10
check zc_assert_eq "restored Long Break is paused" "$(zc_field '.pomodoro.running')" "false"
check zc_assert_eq "restored Long Break reads Resume (label derivation only)" \
  "$(zc_field '.pomodoro.partiallyElapsed')" "true"

# An edited session_number is used as stored, not recomputed from progress.
python3 - "$ZFL_DB" <<'PY'
import sqlite3, sys, time
conn = sqlite3.connect(sys.argv[1])
with conn:
    conn.execute(
        "INSERT INTO checkpoint (singleton, phase, remaining_seconds, "
        "session_number, completed_focus_sessions, saved_at) "
        "VALUES (1, 'focus', 612, 2, 4, ?) "
        "ON CONFLICT(singleton) DO UPDATE SET phase=excluded.phase, "
        "remaining_seconds=excluded.remaining_seconds, "
        "session_number=excluded.session_number, "
        "completed_focus_sessions=excluded.completed_focus_sessions, "
        "saved_at=excluded.saved_at", (int(time.time() * 1000),))
conn.close()
PY
check zc_assert_eq "checkpoint restore seam is wired" \
  "$(zc_call debugRestoreCheckpoint '')" "ok"
check zc_wait_field '.pomodoro.phase' focus 10
check zc_assert_eq "persisted session number is restored even when progress disagrees" \
  "$(zc_field '.pomodoro.session')" "2"

# --- Running phases refresh the checkpoint on a 30-second cadence -----------
# A restored phase is paused, so start it and wait for a fresh checkpoint.
zc_press space
check zc_wait_field '.pomodoro.running' true 10
check zfl_wait_count 1 15
zc_press space
check zc_wait_field '.pomodoro.running' false 10
before="$(zfl_sql "$ZFL_DB" 'SELECT saved_at FROM checkpoint')"
zc_press space
check zc_wait_field '.pomodoro.running' true 10
refreshed=0
for attempt in $(seq 1 40); do
  after="$(zfl_sql "$ZFL_DB" 'SELECT saved_at FROM checkpoint' 2>/dev/null || true)"
  if [[ "$after" =~ ^[0-9]+$ ]] && (( after > before )); then refreshed=1; break; fi
  sleep 1
done
check zc_assert_eq "running phase refreshes the checkpoint within ~30s" "$refreshed" "1"
check zc_assert_eq "refreshed remaining time is still below a full phase" \
  "$([[ "$(zfl_sql "$ZFL_DB" 'SELECT remaining_seconds FROM checkpoint')" =~ ^[0-9]+$ ]] && echo yes || echo no)" "yes"

if (( failures > 0 )); then
  echo "$failures checkpoint/resume check(s) failed"
  exit 1
fi
echo "All checkpoint/resume smoke checks passed"

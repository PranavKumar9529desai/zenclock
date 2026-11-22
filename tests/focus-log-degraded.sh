#!/usr/bin/env bash
# Focus Log degradation smoke test.
#
# Redirect the adapter to an isolated database, corrupt it, then verify through
# the existing shell IPC + state() seam that storage reports a degraded status
# while timers, Pomodoro Cycles and audio cues keep behaving exactly as before.
# The user's real Focus Log is never touched. Run on the live Omarchy desktop:
# ./tests/focus-log-degraded.sh
set -uo pipefail

source "$(dirname "$0")/adapter.sh"

failures=0
check() { "$@" || failures=$((failures + 1)); }
eq() { zc_assert_eq "$@"; }

original_path=""
tmpdir=""
cleanup() {
  # Always point the adapter back at the real database before leaving.
  if [[ -n "$original_path" ]]; then
    zc_call debugSetFocusLogPath "$original_path" >/dev/null 2>&1 || true
  fi
  [[ -n "$tmpdir" ]] && rm -rf "$tmpdir"
  zc_call debugSetEventCapture false >/dev/null 2>&1 || true
  zc_call debugResetAll '' >/dev/null 2>&1 || true
  zc_hide >/dev/null 2>&1 || true
}
trap cleanup EXIT

zc_hide >/dev/null
check zc_wait_field '.serviceReady' true 10
zc_call debugResetAll '' >/dev/null
zc_call debugSetEventCapture true >/dev/null
sleep 0.4

check zc_has_field focusLog
original_path="$(zc_field '.focusLog.path')"
check eq "Focus Log path is reported" \
  "$([[ "$original_path" == *zenclock/focus-log.sqlite3 ]] && echo yes || echo no)" "yes"
check eq "storage starts healthy" "$(zc_field '.focusLog.status')" "ok"

# Isolate the failure: a throwaway database that the helper creates on demand.
tmpdir="$(mktemp -d)"
isolated_db="$tmpdir/focus-log.sqlite3"
zc_call debugSetFocusLogPath "$isolated_db" >/dev/null
check zc_wait_field '.focusLog.status' ok 10
check eq "isolated database is reported" "$(zc_field '.focusLog.path')" "$isolated_db"

# Corrupt the throwaway artifact with non-SQLite bytes. Between commands the
# helper closes its connection, so the file is safe to overwrite here.
printf 'not a sqlite database\n' > "$isolated_db"

# Drive a Focus Session completion through the existing service debug seam.
fake_event='{"sessionId":"zc-degraded-f1","durationMinutes":25,"timestamp":1730000000123}'
zc_call debugRedeliverFocus "$fake_event" >/dev/null
check zc_wait_field '.focusLog.status' degraded 10
reason="$(zc_field '.focusLog.statusReason')"
check eq "degraded status carries a logged reason" \
  "$([[ -n "$reason" && "$reason" != "null" ]] && echo yes || echo no)" "yes"
check eq "degraded adapter writes no Focus Record" "$(zc_field '.focusLog.counts.focus')" "0"

# Timers keep ticking while storage is degraded.
first_time="$(zc_field '.time')"
check zc_wait_changed '.time' "$first_time" 10

# Pomodoro Cycles keep advancing and still request audio cues.
cues_before="$(zc_call debugCueCount '')"
for _ in 1 2 3 4 5 6 7 8; do zc_call debugAdvancePhase '' >/dev/null; done
cycle_events="$(zc_events | jq -r 'map(select(.type == "cycleFinished")) | length')"
check eq "Pomodoro Cycle still completes while degraded" \
  "$([[ "$cycle_events" -ge 1 ]] && echo yes || echo no)" "yes"
cues_after="$(zc_call debugCueCount '')"
check eq "audio cues still fire while degraded" \
  "$([[ "$cues_after" -gt "$cues_before" ]] && echo yes || echo no)" "yes"

# The Timer countdown remains usable and still fires its cue.
check eq "timer preset still works while degraded" "$(zc_call debugSetTimerPreset 5)" "true"
cues_before_timer="$(zc_call debugCueCount '')"
zc_call debugExpireTimer '' >/dev/null
cues_after_timer="$(zc_call debugCueCount '')"
check eq "countdown cue still fires while degraded" \
  "$([[ "$cues_after_timer" -gt "$cues_before_timer" ]] && echo yes || echo no)" "yes"

# Storage is still degraded after all of that activity; nothing recovered by accident.
check eq "storage remains degraded" "$(zc_field '.focusLog.status')" "degraded"

if (( failures > 0 )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All Focus Log degradation checks passed"

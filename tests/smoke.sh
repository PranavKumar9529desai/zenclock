#!/usr/bin/env bash
# End-to-end smoke test through the plugin's public state()/IPC seam.
# Run on the live Omarchy desktop: ./tests/smoke.sh
set -uo pipefail

source "$(dirname "$0")/adapter.sh"

failures=0
check() { "$@" || failures=$((failures + 1)); }
eq() { zc_assert_eq "$@"; }
contains() { zc_assert_contains "$@"; }

# IPC teardown only: never type synthetic keys into an unfocused window.
cleanup() { zc_hide 2>/dev/null || true; }
trap cleanup EXIT

# Baseline: hidden overlay. Engines deliberately keep their state while hidden,
# so reset them through the test seam before asserting from known values.
zc_hide
zc_call debugResetAll '' >/dev/null
sleep 0.4
check eq "overlay starts hidden" "$(zc_field '.opened')" "false"

# Summon and verify the primary display.
zc_toggle
sleep 0.7
check eq "overlay opens" "$(zc_field '.opened')" "true"
check eq "12-hour format by default" "$(zc_field '.format')" "12h"
check contains "timezone badge is populated" "$(zc_field '.timezone')" "(UTC"
check eq "overlay targets a focused monitor" \
  "$([[ -n "$(zc_field '.screen')" ]] && echo set || echo empty)" "set"
check eq "chime availability is reported" \
  "$([[ "$(zc_field '.cueAvailable')" == "true" || "$(zc_field '.cueAvailable')" == "false" ]] && echo reported || echo missing)" "reported"

first_time="$(zc_field '.time')"
check zc_wait_changed '.time' "$first_time" 10

# Zen Inactivity: keyboard wake and pointer wake over a faded control.
if zc_has_field zenActive; then
  sleep 3.4
  check eq "HUD fades after 3s idle" "$(zc_field '.zenActive')" "true"
  zc_key a
  check zc_wait_field '.zenActive' false 10

  sleep 3.4
  check eq "HUD fades again" "$(zc_field '.zenActive')" "true"
  # Pointer wake is wired through each MouseArea's onPositionChanged, but this
  # machine's Hyprland build cannot inject synthetic pointer motion without
  # disturbing keyboard focus, so it is verified by review rather than here.
  echo "SKIP pointer-wake check: no safe synthetic pointer injection"
fi

# Pomodoro engine: focus countdown and the full 4-session cycle.
if zc_has_field mode; then
  zc_key 2
  check zc_wait_field '.mode' pomodoro 10
  check eq "Focus Session starts at 25:00" "$(zc_field '.pomodoro.remaining')" "25:00"

  zc_key space
  check zc_wait_field '.pomodoro.running' true 10
  started="$(zc_field '.pomodoro.remaining')"
  check zc_wait_changed '.pomodoro.remaining' "$started" 12

  zc_key r
  check zc_wait_field '.pomodoro.remaining' 25:00 10
  check eq "R pauses the timer" "$(zc_field '.pomodoro.running')" "false"

  # Drive the deadline machine directly; no 100-minute waits.
  zc_call debugAdvancePhase ''
  check eq "focus 1 ends in Short Break" "$(zc_field '.pomodoro.phase')" "shortBreak"
  check eq "Short Break is session 1 of 4" "$(zc_field '.pomodoro.session')" "1"
  zc_call debugAdvancePhase ''
  check eq "Short Break returns to Focus Session" "$(zc_field '.pomodoro.phase')" "focus"
  check eq "next Focus Session is 2 of 4" "$(zc_field '.pomodoro.session')" "2"

  for _ in 1 2 3 4 5; do zc_call debugAdvancePhase '' >/dev/null; done
  check eq "4th Focus Session ends in Long Break" "$(zc_field '.pomodoro.phase')" "longBreak"
  check eq "Long Break is session 4 of 4" "$(zc_field '.pomodoro.session')" "4"
  zc_call debugAdvancePhase ''
  check eq "Long Break halts the Pomodoro Cycle" "$(zc_field '.pomodoro.phase')" "cycleComplete"
  check eq "halted cycle is flagged" "$(zc_field '.pomodoro.cycleHalted')" "true"
  sleep 1.2
  check eq "cycle never auto-restarts" "$(zc_field '.pomodoro.phase')" "cycleComplete"

  zc_key 1
  check zc_wait_field '.mode' clock 10
fi

# Countdown Timer: presets, custom range and completion.
if zc_has_field mode; then
  zc_key 3
  check zc_wait_field '.mode' timer 10
  check eq "default preset is 5 minutes" "$(zc_field '.timer.remaining')" "05:00"

  zc_call debugSetTimerPreset 15 >/dev/null
  check eq "preset sets 15 minutes" "$(zc_field '.timer.remaining')" "15:00"
  check eq "preset is not custom" "$(zc_field '.timer.custom')" "false"
  zc_call debugSetCustomMinutes 42 >/dev/null
  check eq "custom sets 42 minutes" "$(zc_field '.timer.remaining')" "42:00"
  check eq "custom is flagged" "$(zc_field '.timer.custom')" "true"
  check eq "out-of-range custom is rejected" "$(zc_call debugSetCustomMinutes 999)" "false"

  zc_key space
  check zc_wait_field '.timer.running' true 10
  zc_key r
  check zc_wait_field '.timer.remaining' 42:00 10
  zc_call debugExpireTimer ''
  check eq "countdown reaches 00:00" "$(zc_field '.timer.remaining')" "00:00"
  check eq "countdown stops at zero" "$(zc_field '.timer.running')" "false"
fi

# Stopwatch: count up and reset.
if zc_has_field mode; then
  zc_key 4
  check zc_wait_field '.mode' stopwatch 10
  check eq "stopwatch starts at 00:00" "$(zc_field '.stopwatch.elapsed')" "00:00"
  zc_key space
  check zc_wait_field '.stopwatch.running' true 10
  started="$(zc_field '.stopwatch.elapsed')"
  check zc_wait_changed '.stopwatch.elapsed' "$started" 12
  zc_key r
  check zc_wait_field '.stopwatch.elapsed' 00:00 10
fi

# Dismissal.
zc_key Escape
check zc_wait_field '.opened' false 10

if (( failures > 0 )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All smoke checks passed"

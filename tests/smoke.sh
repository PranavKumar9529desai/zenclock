#!/usr/bin/env bash
# End-to-end smoke test through the plugin's public state()/IPC seam.
# Run on the live Omarchy desktop: ./tests/smoke.sh
set -uo pipefail

source "$(dirname "$0")/adapter.sh"

failures=0
check() { "$@" || failures=$((failures + 1)); }
eq() { zc_assert_eq "$@"; }
contains() { zc_assert_contains "$@"; }

cleanup() {
  zc_key 1 2>/dev/null || true   # back to Clock, if mode switching exists
  zc_hide 2>/dev/null || true
}
trap cleanup EXIT

# Baseline: hidden overlay.
zc_hide
sleep 0.4
check eq "overlay starts hidden" "$(zc_field '.opened')" "false"

# Summon and verify the primary display.
zc_toggle
sleep 0.5
check eq "overlay opens" "$(zc_field '.opened')" "true"
check eq "12-hour format by default" "$(zc_field '.format')" "12h"
check contains "timezone badge is populated" "$(zc_field '.timezone')" "(UTC"

first_time="$(zc_field '.time')"
sleep 1.3
check eq "clock ticks every second" "$([[ "$(zc_field '.time')" != "$first_time" ]] && echo changed || echo stale)" "changed"

# Zen Inactivity (Ticket 2), when present.
if zc_has_field zenActive; then
  sleep 3.4
  check eq "HUD fades after 3s idle" "$(zc_field '.zenActive')" "true"
  zc_key a
  sleep 0.3
  check eq "any key restores HUD" "$(zc_field '.zenActive')" "false"
fi

# Pomodoro engine (Ticket 3), when present.
if zc_has_field mode; then
  zc_key 2
  sleep 0.3
  check eq "key 2 selects Pomodoro" "$(zc_field '.mode')" "pomodoro"
  check eq "Focus Session starts at 25:00" "$(zc_field '.pomodoro.remaining')" "25:00"

  zc_key space
  check eq "Space starts the timer" "$(zc_field '.pomodoro.running')" "true"
  started="$(zc_field '.pomodoro.remaining')"
  sleep 1.6
  check eq "Focus Session counts down" "$([[ "$(zc_field '.pomodoro.remaining')" != "$started" ]] && echo changed || echo stale)" "changed"

  zc_key r
  sleep 0.3
  check eq "R resets the Focus Session" "$(zc_field '.pomodoro.remaining')" "25:00"
  check eq "R pauses the timer" "$(zc_field '.pomodoro.running')" "false"

  zc_key 1
  sleep 0.3
  check eq "key 1 returns to Clock" "$(zc_field '.mode')" "clock"
fi

# Dismissal.
zc_key Escape
sleep 0.4
check eq "Esc dismisses the overlay" "$(zc_field '.opened')" "false"

if (( failures > 0 )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All smoke checks passed"

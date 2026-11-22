#!/usr/bin/env bash
# Test adapter for Zen Clock.
#
# Interface (the seam tests cross): the running Omarchy shell's IPC and the
# plugin's `state()` JSON. Inputs are `toggle`/`hide`/`call` plus real keystrokes
# via wtype. Nothing here inspects the QML visual tree, so the tests keep working
# when the HUD layout changes.
#
# Optional features from later tickets are discovered with `zc_has_field`, so
# this adapter works against the base plugin as well as the integrated build.

ZC_PLUGIN_ID="${ZC_PLUGIN_ID:-pranav.zenclock}"
ZC_IPC_TIMEOUT="${ZC_IPC_TIMEOUT:-8}"

zc_ipc() {
  local attempt
  for attempt in 1 2 3; do
    if timeout "$ZC_IPC_TIMEOUT" omarchy-shell shell "$@" 2>/dev/null; then
      return 0
    fi
    sleep 0.4
  done
  echo "zc_ipc failed: omarchy-shell shell $*" >&2
  return 1
}

zc_state()        { zc_ipc call "$ZC_PLUGIN_ID" state ''; }
zc_field()        { zc_state | jq -r "$1"; }
zc_has_field()    { zc_state | jq -e --arg key "$1" 'has($key)' >/dev/null 2>&1; }
zc_toggle()       { zc_ipc toggle "$ZC_PLUGIN_ID"; }
zc_hide()         { zc_ipc hide "$ZC_PLUGIN_ID"; }
zc_call()         { local method="${1:-}"; zc_ipc call "$ZC_PLUGIN_ID" "$method" "${2:-}"; }
# Never inject synthetic keys into whatever window happens to have focus.
zc_key() {
  if [[ "$(zc_field '.opened' 2>/dev/null || true)" != "true" ]]; then
    echo "zc_key refused: overlay is not open" >&2
    return 1
  fi
  wtype -k "$1"
}

# Poll until a JSON field changes from its previous value.
zc_wait_changed() {
  local filter="$1" previous="$2" attempts="${3:-15}" actual=""
  while (( attempts > 0 )); do
    actual="$(zc_field "$filter" 2>/dev/null || true)"
    [[ -n "$actual" && "$actual" != "$previous" ]] && return 0
    sleep 0.2
    attempts=$((attempts - 1))
  done
  echo "timeout waiting for $filter to change from $previous (last: $actual)" >&2
  return 1
}

# Poll until a JSON field reaches the expected value.
zc_wait_field() {
  local filter="$1" expected="$2" attempts="${3:-25}" actual=""
  while (( attempts > 0 )); do
    actual="$(zc_field "$filter" 2>/dev/null || true)"
    [[ "$actual" == "$expected" ]] && return 0
    sleep 0.2
    attempts=$((attempts - 1))
  done
  echo "timeout waiting for $filter == $expected (last: $actual)" >&2
  return 1
}

zc_assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s: expected %q, got %q\n' "$label" "$expected" "$actual"
    return 1
  fi
}

zc_assert_contains() {
  local label="$1" actual="$2" needle="$3"
  if [[ "$actual" == *"$needle"* ]]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s: expected %q to contain %q\n' "$label" "$actual" "$needle"
    return 1
  fi
}

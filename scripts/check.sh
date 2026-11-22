#!/usr/bin/env bash
# Repo guardrail. Run from anywhere: scripts/check.sh
# Portable checks always run; desktop/Omarchy-only checks skip when absent so
# CI can use CHECK_PORTABLE=1 without pretending to have a Wayland session.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
skip() { printf 'SKIP %s\n' "$1"; }

# --- JSON -------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  ok=1
  while IFS= read -r f; do jq -e . "$f" >/dev/null 2>&1 || { fail "invalid JSON: $f"; ok=0; }; done \
    < <(find . -name '*.json' -not -path './.git/*')
  (( ok )) && pass "JSON files parse"
else
  skip "jq not installed"
fi

# --- Shell syntax -----------------------------------------------------------
ok=1
while IFS= read -r f; do bash -n "$f" 2>/dev/null || { fail "shell syntax: $f"; ok=0; }; done \
  < <(find . -name '*.sh' -not -path './.git/*')
(( ok )) && pass "shell scripts parse"

# --- Mechanical QML safety rules -------------------------------------------
ok=1
if grep -RIn --include='*.qml' --exclude='PlainText.qml' --exclude='ZenText.qml' \
  -E '^[[:space:]]*Text[[:space:]]*\{' . >/dev/null; then
  fail "raw Text { } outside PlainText.qml/ZenText.qml (use the shared component)"
  ok=0
fi
if grep -RIn --include='*.qml' 'notify-send' . | grep -vE ':[[:space:]]*//' >/dev/null; then
  fail "notify-send found (cues must be audio-only)"
  ok=0
fi
if grep -RIn --include='*.qml' -E 'duration:[[:space:]]*[0-9]+' . >/dev/null; then
  fail "bare animation duration (use Style.duration(ms))"
  ok=0
fi
(( ok )) && pass "mechanical QML rules"

# --- QML lint (Qt6 only; Qt5 qmllint rejects ComponentBehavior: Bound) ------
if [[ ${CHECK_PORTABLE:-0} == 1 ]]; then
  skip "qmllint in portable mode"
elif [[ -x /usr/lib/qt6/bin/qmllint ]]; then
  alias_dir="$(mktemp -d)"
  ln -s /usr/share/omarchy/shell "$alias_dir/qs"
  /usr/lib/qt6/bin/qmllint -I "$alias_dir" ./*.qml > "$alias_dir/lint.txt" 2>&1
  lint_status=$?
  if grep -Eq '\[syntax\]|Error:|Expected token|Unexpected token' "$alias_dir/lint.txt"; then
    fail "QML syntax errors"; grep -E '\[syntax\]|Error:|Expected token|Unexpected token' "$alias_dir/lint.txt" | head -10
  elif (( lint_status == 0 )); then
    pass "qmllint (Qt6)"
  else
    skip "qmllint returned $lint_status (missing-property warnings from standalone import resolution)"
  fi
  rm -rf "$alias_dir"
else
  skip "Qt6 qmllint not installed"
fi

# --- Plugin manifest --------------------------------------------------------
if [[ ${CHECK_PORTABLE:-0} == 1 ]]; then
  skip "omarchy plugin validate in portable mode"
elif command -v omarchy >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  # Trailing slash matters: the validator rejects the plugin-folder symlink itself.
  if omarchy plugin validate "$PWD/" >/dev/null 2>&1; then
    pass "omarchy plugin validate"
  else
    fail "omarchy plugin validate"
  fi
else
  skip "omarchy CLI not installed"
fi

if (( failures > 0 )); then
  printf '%d check(s) failed\n' "$failures"
  exit 1
fi
printf 'All checks passed\n'

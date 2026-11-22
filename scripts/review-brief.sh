#!/usr/bin/env bash
# Build a review brief: open issues, closed ticket titles, and the net diff.
# Paste the output into the reviewer agent's prompt so it sees the spec.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

base="${1:-master}"
echo "=== OPEN ISSUES ==="
gh issue list --state open --json number,title,body \
  --jq '.[] | "#\(.number) \(.title)\n\(.body)\n"' 2>/dev/null || echo "(gh unavailable)"

echo "=== ALL ISSUES (titles) ==="
gh issue list --state all --limit 100 2>/dev/null || true

echo "=== NET DIFF vs $base ==="
git diff --stat "$base"...HEAD 2>/dev/null || git diff --stat "$base" HEAD
git diff "$base"...HEAD 2>/dev/null || git diff "$base" HEAD

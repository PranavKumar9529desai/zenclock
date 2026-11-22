# Zen Clock

Distraction-free fullscreen HUD clock, Pomodoro, and productivity timer overlay for Omarchy.

## Agent skills

### Issue tracker

GitHub issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical 5-role vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout (`GLOSSARY.md` and `docs/adr/` at root). See `docs/agents/domain.md`.

### HUD visibility and timing

Before changing HUD visibility, idle timers, focus, or their tests, read `docs/BEHAVIOR.md`.

### Review

Reviewers read `CODING_STANDARDS.md` and build the spec-plus-diff brief with `scripts/review-brief.sh`.

### Checks

Run `scripts/check.sh` before committing; the pre-commit hook and CI run it too.

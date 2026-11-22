# Coding standards (read during review)

Mechanical rules live in `scripts/check.sh` and are enforced by the pre-commit
hook and CI. This file holds only judgement calls that a deterministic check
cannot replace.

## Review rules

- **First frame before transitions.** For any timed, idle-driven, or stateful UI
  behavior, verify the first rendered frame explicitly, not just the boolean
  state that drives it. A test that only asserts `zenActive` can pass while the
  HUD is invisible.
- **Observable over internal.** Assert the externally visible result of a state
  change (opacity, text, mode) rather than the flag that produced it.
- **Stale state across test runs.** Every test-only reset must leave engines in
  their default phase, not merely "not running". The service is kept loaded,
  so a previous run's phase survives into the next one.
- **Reveal before action.** When a control is visually hidden, the first input
  reveals it; the second input performs the action. Both a parked pointer and
  a pointer moving onto the control must behave the same way.
- **Docs are part of the change.** When behavior changes, update `GLOSSARY.md`,
  `docs/BEHAVIOR.md`, the relevant ADR, and `tests/README.md` in the same
  commit. ADRs that describe unimplemented designs must say so.

Reviewers: gather the spec and the net diff with `scripts/review-brief.sh`
before reviewing. Reviewing source alone is not sufficient.

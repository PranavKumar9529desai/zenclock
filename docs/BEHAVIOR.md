# HUD behavior: visible states and timing

This is the authoritative description of when Zen Clock's secondary HUD is
visible. Read it before changing visibility, timers, input handling, or the
tests that cover them.

## Definitions

- **Primary display**: the clock digits or the active mode's digits. Always
  visible while the overlay is open.
- **Secondary HUD**: mode pills, title, timezone badge, action buttons, hints,
  and the mouse cursor.

## Timeline for one opening

| Time | State |
|---|---|
| `SUPER + Z` → panel visible | Secondary HUD fully visible (opacity 1), normal cursor, Clock mode by default |
| next 8 seconds | Grace period. HUD stays visible even with no input |
| after grace + 3 seconds idle | Zen Inactivity: HUD fades to 0 in 120 ms, cursor blanks, primary digits stay |
| any real mouse movement / keypress | HUD returns in 180 ms, idle countdown restarts |
| while Zen is active | Clicking a faded control only reveals the HUD; it never triggers the action. A 400 ms just-woke window keeps this true for a pointer already parked on the control |
| `Esc` / `SUPER + Z` | Overlay dismisses; timers keep running in the service |

## Invariants

1. The first rendered frame of every opening has the HUD visible.
2. `zenActive == false` implies HUD opacity 1; `zenActive == true` implies
   opacity 0. No path may leave them disagreeing (this happened once when a
   one-shot animation kept running after a false wake).
3. Fading never hides the primary digits.
4. Hover/cursor changes caused by a fade are not user input and must not wake
   Zen.
5. Tests must assert observable opacity, not only the `zenActive` boolean.

`state()` exposes `zenActive` and `hudOpacity` for these assertions.

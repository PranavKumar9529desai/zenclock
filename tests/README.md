# Zen Clock test adapter

## The seam

Tests cross one interface: the running Omarchy shell's IPC plus the plugin's
`state()` JSON.

```
tests/smoke.sh ──▶ tests/adapter.sh ──▶ omarchy-shell shell call pranav.zenclock state ''
                                  ├──▶ omarchy-shell shell toggle|hide|call
                                  └──▶ wtype  (real keys)
```

`state()` reports externally visible state only — `opened`, `format`, `time`,
`timezone`, and, when later tickets are loaded, `zenActive`, `mode`, and
`pomodoro`. No test reaches into the QML visual tree, so HUD restyling cannot
break them.

## Interface exposed by `adapter.sh`

| Function | Purpose |
|---|---|
| `zc_state` | Raw `state()` JSON |
| `zc_field <jq-filter>` | One field as text |
| `zc_has_field <name>` | Feature detection (base plugin vs integrated build) |
| `zc_toggle` / `zc_hide` | Summon / dismiss through the shell |
| `zc_call <method> [arg]` | Invoke a plugin method |
| `zc_key <wtype-key>` | Send a real keystroke |
| `zc_wait_field <filter> <value> [attempts]` | Poll until state settles |
| `zc_wait_changed <filter> <previous> [attempts]` | Poll until a clock/timer advances |
| `zc_assert_eq` / `zc_assert_contains` | Assertions |

`zc_key` refuses to inject anything unless `state().opened` is true, so a
failed run cannot type into an unrelated focused window. `zc_press` re-summons
the overlay first, which keeps the suite resilient to someone dismissing it
mid-run from the desktop. Teardown uses IPC `hide`, never synthetic keys.

## Test-only plugin seams

`state()` also reports `screen`, `cueAvailable` and `serviceReady`. The plugin
exposes these debug methods through shell IPC, used only by `smoke.sh`:
`debugResetAll`, `debugAdvancePhase`, `debugSetTimerPreset`,
`debugSetCustomMinutes`, `debugExpireTimer`, `debugSetEventCapture`,
`debugEventsJson` and `debugRestoreCheckpoint`. They let the deadline-based
state machines be driven without waiting through a 100-minute cycle.
`debugRestoreCheckpoint` re-runs the load path; `checkpoint-resume.sh` observes
the result through `state()` JSON and the SQLite file, never the visual tree.

`debugSetEventCapture` enables a **test-only** event log. V1 stores no events in
production: the service simply forwards the engines' signals, so a V2 database
adapter can connect at that seam. The test adapter reads the captured events
with `zc_events` and asserts their type and metadata.

`debugSetFocusLogPath` redirects Focus Log writes to an isolated database so the
degradation test (`tests/focus-log-degraded.sh`) can corrupt storage without
touching the user's real Focus Log; `debugCueCount` counts requested audio cues
at the service event seam so the same test can prove cues still fire while
storage is degraded. A failed write is reported in `state().focusLog.status` as
`degraded` with the reason in `statusReason`.

`state()` also reports `hudOpacity`. The smoke test asserts the HUD is visible
immediately after open and stays visible through the 8-second grace period;
only after the 3-second idle timeout does it fade. A click on a faded control
reveals the HUD without triggering the action.

Synthetic pointer motion is not injected: this machine's Hyprland build cannot
move the cursor without disturbing keyboard focus, so pointer-driven Zen wake
is verified in code review. Keyboard wake is covered by the smoke test.

## Running

On the live Omarchy desktop, with the plugin enabled:

```bash
./tests/smoke.sh
```

The script toggles the overlay, checks the clock and Timezone Badge, verifies
Zen Inactivity and Pomodoro when those fields exist, and dismisses the overlay.
It returns to Clock and hides the overlay on exit even if a check fails.

Override `ZC_PLUGIN_ID` when testing a renamed plugin build.

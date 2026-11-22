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
failed run cannot type into an unrelated focused window. Teardown uses IPC
`hide`, never synthetic keys.

## Test-only plugin seams

`state()` also reports `screen` and `cueAvailable`. The plugin exposes five
debug methods through shell IPC, used only by `smoke.sh`: `debugResetAll`,
`debugAdvancePhase`, `debugSetTimerPreset`, `debugSetCustomMinutes`, and
`debugExpireTimer`. They let the deadline-based state machines be driven
without waiting through a 100-minute cycle. No analytics or event storage is
added by these methods.

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

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
| `zc_assert_eq` / `zc_assert_contains` | Assertions |

## Running

On the live Omarchy desktop, with the plugin enabled:

```bash
./tests/smoke.sh
```

The script toggles the overlay, checks the clock and Timezone Badge, verifies
Zen Inactivity and Pomodoro when those fields exist, and dismisses the overlay.
It returns to Clock and hides the overlay on exit even if a check fails.

Override `ZC_PLUGIN_ID` when testing a renamed plugin build.

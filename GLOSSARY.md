# Zen Clock

Distraction-free fullscreen HUD clock, Pomodoro, and productivity timer overlay for Omarchy.

## Language

**Zen Clock**:
A fullscreen layer-shell overlay (`WlrLayer.Overlay`) providing aesthetic digital time and focus tracking on demand.
_Avoid_: Wallpaper widget, background window, tray app

**Focus Session**:
A 25-minute continuous work interval within a Pomodoro cycle.
_Avoid_: Pomodoro tick, work interval, sprint

**Short Break**:
A 5-minute rest period between individual focus sessions within a cycle.
_Avoid_: Mini break, intermission

**Pomodoro Cycle**:
A bounded series of 4 focus sessions ending in a Long Break, halting on completion until manual confirmation to start a new cycle.
_Avoid_: Pomodoro set, repetition loop

**Long Break**:
A 30-minute extended rest period that occurs only upon completing a full 4-session Pomodoro cycle.
_Avoid_: Extended rest, big break

**Zen Inactivity**:
A clean presentation state entered after 3 seconds of user inactivity where HUD navigation, action buttons, and cursor fade away, leaving only primary time digits visible.
_Avoid_: Sleep mode, screensaver, dark mode

**Timezone Badge**:
A HUD indicator showing the system's active IANA timezone and UTC offset (e.g. `Asia/Kolkata • IST (UTC+05:30)`).
_Avoid_: World clock, local time label

**Font Glyphs**:
Native Nerd Font glyphs and text symbols used directly within `PlainText` for all UI icons (mode indicators, play/pause, reset), avoiding any icon libraries, SVGs, or external asset dependencies.
_Avoid_: Icon libraries, SVG icons, bitmap assets

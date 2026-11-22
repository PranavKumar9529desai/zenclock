# Spec: Zen Clock & Multi-Mode Focus Overlay

## Problem Statement

Users working on desktop environments often get distracted by notifications, cluttered status bars, open browser tabs, and desktop windows while attempting to maintain deep focus or time their sessions. Standard desktop clocks and timers either crowd the screen as persistent floating windows or remain hidden in tiny system trays, lacking a dedicated, full-screen immersion mode that provides an aesthetic, distraction-free view of time, Pomodoro cycles, countdowns, and stopwatches.

## Solution

Zen Clock is a full-screen, layer-shell overlay plugin for Omarchy. It allows users to press a simple hotkey (`SUPER + Z`) to instantly blanket the active monitor with an aesthetic, dark-themed HUD. The overlay provides four distinct modes—Digital Clock, Pomodoro, Countdown Timer, and Stopwatch. It incorporates an automated Zen Inactivity mode where all UI controls and the mouse cursor smoothly fade away after 3 seconds of idle time, leaving only glowing digits visible. The Pomodoro workflow implements a 4-session cycle ending in a 30-minute long break, with gentle audio-only cues, no visual popup distractions, and native font glyphs for zero external asset dependencies.

## User Stories

1. As a focused developer, I want to press `SUPER + Z` from any application, so that I can instantly view a full-screen, distraction-free clock and timer overlay without switching virtual workspaces.
2. As a user, I want the overlay to open by default to an aesthetic digital clock, so that I have a clean and visually pleasing full-screen display of current time and date.
3. As a user, I want to see a subtle Timezone Badge indicating my active system timezone and UTC offset, so that I can verify my local time context at a glance.
4. As a user, I want the clock to display in 12-hour format with an AM/PM indicator by default, so that it matches my standard time-reading preference.
5. As a user, I want to toggle between 12-hour and 24-hour time formats, so that I can view military time if preferred.
6. As a deep-work practitioner, I want to switch to Pomodoro mode via a mode pill or pressing `2`, so that I can structure my work into dedicated focus intervals.
7. As a Pomodoro user, I want focus sessions to last 25 minutes, so that I work in optimal focused sprints.
8. As a Pomodoro user, I want short breaks of 5 minutes between sessions, so that I have regular rest intervals to maintain mental clarity.
9. As a Pomodoro user, I want short breaks to begin automatically when a focus session finishes, so that I am encouraged to immediately step away.
10. As a Pomodoro user, I want an audio cue to chime when a focus session or break ends, so that I am notified even if looking away from the screen.
11. As a Pomodoro user, I want zero desktop notification popups to appear upon timer completion, so that my focus is not broken by floating notifications or tray popups.
12. As a Pomodoro user, I want a Pomodoro Cycle to consist of exactly 4 focus sessions, so that I follow a standard, productive daily interval set.
13. As a Pomodoro user, I want a 30-minute Long Break after completing 4 consecutive focus sessions, so that I get a restorative rest after a large block of work.
14. As a Pomodoro user, I want the timer to halt after the 4th session's long break completes and prompt me before starting a new cycle, so that the timer does not run endlessly unattended.
15. As a user, I want to switch to a Countdown Timer mode via a mode pill or pressing `3`, so that I can set arbitrary time countdowns.
16. As a timer user, I want quick preset buttons for 5m, 15m, 25m, 45m, and 60m, so that I can start a timer with a single click.
17. As a timer user, I want to enter custom minutes for the countdown timer, so that I can time non-standard activities.
18. As a user, I want to switch to a Stopwatch mode via a mode pill or pressing `4`, so that I can measure elapsed time cleanly in `MM:SS`.
19. As a user in any timer mode, I want to press `Space` to toggle between Play and Pause, so that I can operate the timer using the keyboard.
20. As a user in any timer mode, I want to press `R` to reset the active timer or stopwatch, so that I can quickly start over without touching the mouse.
21. As a user, I want all navigation pills, control buttons, badges, and the mouse cursor to smoothly fade away after 3 seconds of inactivity, so that my screen displays only pure, distraction-free digits.
22. As a user in Zen Inactivity mode, I want any mouse movement or keypress to immediately restore full visibility of all controls, so that I can interact with the overlay without lag.
23. As a user, I want to press `Esc` at any time, so that I can dismiss the overlay immediately and return to my active desktop windows.
24. As a user, I want running timers to continue ticking in the background when the overlay is dismissed, so that I can work on my desktop while the countdown progresses.
25. As a user, I want background timers to play the completion chime even when the overlay is dismissed, so that I know when my session or break has ended.
26. As a multi-monitor user, I want the overlay to appear on my currently active/focused monitor, so that it displays right where my eyes and input focus are.
27. As a user, I want all icons in the UI to be rendered using native font glyphs (Nerd Font / Unicode) rather than external image or SVG libraries, so that the plugin remains lightweight, crisp, and fast.
28. As a future user, I want the domain model to emit clean session completion events, so that a future SQLite analytics logging module can be plugged in without refactoring the overlay UI.

## Implementation Decisions

- **Overlay Window Architecture**: Built as a Quickshell layer-shell overlay plugin (`kind: "overlay"` in `manifest.json`) targeting `WlrLayer.Overlay` with `WlrKeyboardFocus.Exclusive` on the focused monitor (`Quickshell.screens`).
- **Font & Icon Rendering**: All visual glyphs (clock, pomodoro, timer, stopwatch, play, pause, reset) use native Nerd Font / Unicode glyphs rendered through `PlainText` (satisfying Omarchy's `textFormat: Text.PlainText` rule) with zero icon libraries or SVG files.
- **State & Timer Engine**: A decoupled JavaScript/QML state machine manages active mode, countdown/countup intervals, pause states, 4-session cycle tracking, and event signals (`focusSessionCompleted`, `cycleFinished`, `cueRequested`).
- **Zen Inactivity Controller**: A 3-second inactivity timer monitors user inputs (`PointerHandler` / `Keys.onPressed`); on trigger, it animates controls opacity to `0` and hides cursor; on input, opacity smoothly animates back to `1`.
- **Audio Cue Dispatcher**: On timer/session completion, triggers system audio `/usr/share/sounds/freedesktop/stereo/complete.oga` using `canberra-gtk-play` or `paplay`, deliberately avoiding `notify-send`.
- **Timezone Detection**: Automatically reads `/etc/localtime` or uses `Intl.DateTimeFormat().resolvedOptions().timeZone` to display the formatted active timezone.
- **Keyboard Handling**: Global key capture inside the overlay handles `Space` (Play/Pause), `R` (Reset), `1`-`4` (Mode selection), and `Esc` (Dismiss).

## Testing Decisions

- **Testing Principles**: Test only externally visible state and behavior through defined seams, not internal QML visual tree hierarchy.
- **Primary Seam - Timer Engine**:
  - Verify mode transitions between Clock, Pomodoro, Timer, and Stopwatch.
  - Verify Pomodoro phase progression (Focus ➔ Short Break ➔ ... ➔ Session 4 ➔ Long Break ➔ Halt).
  - Verify audio cue trigger condition when countdown hits 0.
  - Verify timer continues state progression when overlay is hidden.
- **Secondary Seam - Omarchy Plugin Validation**:
  - Verify plugin manifest and QML syntax via `omarchy plugin validate`.

## Out of Scope

- Multi-city world clocks or time converter tools.
- Calendar integration or scheduled event alarms.
- Persistent SQLite database analytics in v1 (reserved for future release via the event seam).
- Millisecond precision or lap split tracking in the stopwatch.
- Custom user-uploaded sound packs or ringtones.

## Further Notes

- The plugin directory is developed in `/home/pranav/Work/zenclock` and symlinked to `~/.config/omarchy/plugins/pranav.zenclock`.
- Keybind `SUPER + Z` will be added to `~/.config/hypr/bindings.lua`.

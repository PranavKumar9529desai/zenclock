# 1. Fullscreen Layer-Shell Overlay Architecture

We chose to implement ZenClock as a Quickshell layer-shell overlay plugin (`WlrLayer.Overlay`) running with an in-memory state engine and clean domain event seams.

## Context
The user requires a full-screen, distraction-free clock and multi-mode timer (Clock, Pomodoro, Timer, Stopwatch) that covers the entire desktop on demand, dismisses cleanly on <kbd>Esc</kbd>, and supports future SQLite logging for long-term historical analytics without requiring early database baggage.

## Decision
1. Implement ZenClock as an Omarchy Quickshell overlay plugin (`kind: "overlay"`), bound to `SUPER + Z` and rendered on `WlrLayer.Overlay` with `WlrKeyboardFocus.Exclusive`.
2. Manage session counts and active timer state in memory during v1, while dispatching explicit domain events (`focusSessionCompleted`, `cycleFinished`) to support future SQLite persistence without refactoring UI components.
3. Provide audio-only cues (`canberra-gtk-play -i complete` / bell sound) to protect user focus from desktop notification popups.

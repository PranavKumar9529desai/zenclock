pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// UI-free Pomodoro Cycle state machine. Lives under the always-loaded overlay
// root (keepLoaded: true), so its deadline-based timer keeps advancing even
// while the overlay is dismissed.
Item {
  id: root

  // Domain vocabulary (see GLOSSARY.md): Focus Session, Short Break,
  // Long Break, Pomodoro Cycle.
  property int focusMinutes: 25
  property int shortBreakMinutes: 5
  property int longBreakMinutes: 30
  property int sessionsPerCycle: 4

  // "focus" | "shortBreak" | "longBreak" | "cycleComplete"
  property string phase: "focus"
  property int completedFocusSessions: 0  // 0..4 within the current cycle
  // 1..4 within the current cycle, derived so it can never disagree with the
  // four progress glyphs in the view.
  readonly property int sessionNumber: root.phase === "focus"
    ? Math.min(root.sessionsPerCycle, root.completedFocusSessions + 1)
    : Math.max(1, Math.min(root.sessionsPerCycle, root.completedFocusSessions))
  property int remainingSeconds: focusMinutes * 60
  property bool running: false
  property real deadlineMs: 0             // wall-clock deadline for current phase

  property int totalFocusSessions: 0
  property int totalCycles: 0
  readonly property string runId: "zc-" + Date.now().toString(36)

  readonly property string formattedTime: formatSeconds(root.remainingSeconds)
  readonly property bool cycleHalted: root.phase === "cycleComplete"
  readonly property bool canSkip: root.phase === "shortBreak" || root.phase === "longBreak"

  // Domain event seams for the future SQLite logger (Ticket 5). Timestamps are
  // Unix epoch milliseconds (Date.now()); ids are stable within a shell run.
  signal focusSessionCompleted(string sessionId, int durationMinutes, real timestamp)
  signal cycleFinished(string cycleId, real timestamp)
  // Cue names: "complete" (Focus Session ended), "bell" (break ended).
  // Dispatch is audio-only, e.g.
  // Quickshell.execDetached(["canberra-gtk-play", "-i", "complete"]).
  // Never notify-send / desktop popups.
  signal cueRequested(string cue)

  onCueRequested: function(cue) {
    Quickshell.execDetached(["canberra-gtk-play", "-i", cue])
  }

  function formatSeconds(sec) {
    var s = Math.max(0, Math.floor(sec))
    var m = Math.floor(s / 60)
    var r = s % 60
    return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r
  }

  function durationForPhase(p) {
    if (p === "shortBreak") return root.shortBreakMinutes
    if (p === "longBreak") return root.longBreakMinutes
    return root.focusMinutes
  }

  function beginPhase(p, seconds) {
    root.phase = p
    root.remainingSeconds = seconds
    root.running = true
    root.deadlineMs = Date.now() + seconds * 1000
  }

  // Recompute from the wall clock rather than decrementing, so hidden time
  // and delayed ticks never cause drift. A zero crossing advances the cycle.
  function refreshRemaining() {
    if (!root.running || root.deadlineMs <= 0) return
    var left = Math.max(0, Math.ceil((root.deadlineMs - Date.now()) / 1000))
    root.remainingSeconds = left
    if (left === 0) root.advance()
  }

  function advance() {
    root.deadlineMs = 0
    var nowMs = Date.now()

    if (root.phase === "focus") {
      const sessionId = root.runId + "-f" + (root.totalFocusSessions + 1)
      root.totalFocusSessions++
      root.completedFocusSessions++
      root.focusSessionCompleted(sessionId, root.focusMinutes, nowMs)
      root.cueRequested("complete")

      if (root.completedFocusSessions >= root.sessionsPerCycle)
        root.beginPhase("longBreak", root.longBreakMinutes * 60)
      else
        root.beginPhase("shortBreak", root.shortBreakMinutes * 60)
    } else if (root.phase === "shortBreak") {
      root.cueRequested("bell")
      root.beginPhase("focus", root.focusMinutes * 60)
    } else if (root.phase === "longBreak") {
      root.cueRequested("bell")
      root.haltCycle()
    }
  }

  // End of a Pomodoro Cycle: emit the boundary event and halt on a prompt.
  // Never auto-start the next cycle.
  function haltCycle() {
    var cycleId = root.runId + "-c" + (root.totalCycles + 1)
    root.totalCycles++
    root.cycleFinished(cycleId, Date.now())
    root.phase = "cycleComplete"
    root.remainingSeconds = 0
    root.deadlineMs = 0
    root.running = false
  }

  // Ticket #19 / ADR 0003: the single exception to ADR 0002's no-engine-changes
  // promise. Restores a checkpoint as a PAUSED, partially elapsed phase so the
  // existing primary button already reads "Resume". runId and the lifetime
  // counters are deliberately left fresh; only cycle position is restored.
  function restoreSnapshot(phase, remainingSeconds, completedFocusSessions) {
    if (phase !== "focus" && phase !== "shortBreak" && phase !== "longBreak") return false
    if (!(remainingSeconds > 0) || root.running) return false
    root.phase = phase
    root.completedFocusSessions = Math.max(0,
      Math.min(root.sessionsPerCycle, completedFocusSessions))
    root.remainingSeconds = remainingSeconds
    root.deadlineMs = 0
    root.running = false
    return true
  }

  function start() {
    if (root.phase === "cycleComplete") {
      root.startNewCycle()
      return
    }
    if (root.running) return
    if (root.remainingSeconds <= 0)
      root.remainingSeconds = root.durationForPhase(root.phase) * 60
    root.running = true
    root.deadlineMs = Date.now() + root.remainingSeconds * 1000
  }

  function pause() {
    if (!root.running) return
    root.refreshRemaining()
    root.running = false
    root.deadlineMs = 0
  }

  function toggle() {
    if (root.phase === "cycleComplete") {
      root.startNewCycle()
      return
    }
    if (root.running) root.pause()
    else root.start()
  }

  // Reset only the current phase and pause it; cycle progress is preserved.
  // At the cycle prompt it clears the halt and prepares a fresh, paused
  // Focus Session so the user can confirm with Play / Space.
  function reset() {
    if (root.phase === "cycleComplete") {
      root.completedFocusSessions = 0
      root.phase = "focus"
      root.remainingSeconds = root.focusMinutes * 60
      root.deadlineMs = 0
      root.running = false
      return
    }
    root.running = false
    root.deadlineMs = 0
    root.remainingSeconds = root.durationForPhase(root.phase) * 60
  }

  // Skip is break-only. Skipping the Long Break also halts the cycle: a new
  // Pomodoro Cycle always requires explicit confirmation via startNewCycle().
  function skip() {
    if (root.phase === "shortBreak") {
      root.beginPhase("focus", root.focusMinutes * 60)
    } else if (root.phase === "longBreak") {
      root.haltCycle()
    }
  }

  function startNewCycle() {
    root.completedFocusSessions = 0
    root.beginPhase("focus", root.focusMinutes * 60)
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.running
    onTriggered: root.refreshRemaining()
  }
}

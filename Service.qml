pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// Deep module: owns every timer state machine and the domain event seam.
// The shell loads this service once for the enabled plugin and keeps it alive,
// so deadlines and audio cues keep advancing while the overlay is dismissed.
// The overlay is only a view of this state.
Item {
  id: root

  readonly property alias pomodoroEngine: pomodoro
  readonly property alias timerEngine: countdown
  readonly property alias stopwatchEngine: stopwatch
  readonly property alias focusLog: focusLog

  // V1 forwards events only. V2 connects a concrete database adapter to these
  // signals; there is no sink object and no in-memory analytics store here.
  signal focusSessionCompleted(string sessionId, int durationMinutes, real timestamp)
  signal cycleFinished(string cycleId, real timestamp)
  signal countdownCompleted(int durationMinutes, real timestamp)

  // Checkpoint observation lives here at the service seam: engines and views
  // stay unchanged except for PomodoroEngine.restoreSnapshot (ADR 0003).
  property bool restoringCheckpoint: false
  property string lastPhase: ""
  property int lastRemaining: -1
  property int lastCompleted: -1
  property bool lastRunning: false
  property real lastCheckpointMs: 0

  // Test-only capture, disabled by default, so production V1 keeps no history.
  property bool debugEventCapture: false
  property var debugEvents: []

  function debugEventsJson() { return JSON.stringify(root.debugEvents) }
  function clearDebugEvents() { root.debugEvents = [] }

  PomodoroEngine { id: pomodoro }
  TimerEngine { id: countdown }
  StopwatchEngine { id: stopwatch }

  // V2: the concrete adapter at the seam. The engines and views stay unchanged.
  FocusLog { id: focusLog }

  // Connect at the signal itself so every delivery is recorded, including a
  // redelivered event (INSERT OR IGNORE in the helper makes that idempotent).
  Connections {
    target: root

    function onFocusSessionCompleted(sessionId, durationMinutes, timestamp) {
      focusLog.recordFocus(sessionId, durationMinutes, timestamp)
    }
  }

  Connections {
    target: pomodoro

    function onFocusSessionCompleted(sessionId, durationMinutes, timestamp) {
      root.focusSessionCompleted(sessionId, durationMinutes, timestamp)
      if (root.debugEventCapture)
        root.debugEvents.push({
          type: "focusSessionCompleted",
          sessionId: sessionId,
          durationMinutes: durationMinutes,
          timestamp: timestamp
        })
    }

    function onCycleFinished(cycleId, timestamp) {
      root.cycleFinished(cycleId, timestamp)
      if (root.debugEventCapture)
        root.debugEvents.push({ type: "cycleFinished", cycleId: cycleId, timestamp: timestamp })
    }
  }

  Connections {
    target: countdown

    function onCountdownCompleted(durationMinutes, timestamp) {
      root.countdownCompleted(durationMinutes, timestamp)
      if (root.debugEventCapture)
        root.debugEvents.push({
          type: "countdownCompleted",
          durationMinutes: durationMinutes,
          timestamp: timestamp
        })
    }
  }

  function rememberPomodoro() {
    root.lastPhase = pomodoro.phase
    root.lastRemaining = pomodoro.remainingSeconds
    root.lastCompleted = pomodoro.completedFocusSessions
    root.lastRunning = pomodoro.running
  }

  function saveCheckpoint() {
    focusLog.saveCheckpoint(pomodoro.phase, pomodoro.remainingSeconds,
                            pomodoro.sessionNumber, pomodoro.completedFocusSessions)
    root.lastCheckpointMs = Date.now()
  }

  function checkpointTick() {
    if (root.restoringCheckpoint) return
    var phase = pomodoro.phase
    var resumable = phase === "focus" || phase === "shortBreak" || phase === "longBreak"
    var running = pomodoro.running
    var remaining = pomodoro.remainingSeconds

    if (phase === "cycleComplete") {
      // A halted cycle has no interrupted phase to resume.
      if (root.lastPhase !== "cycleComplete") {
        focusLog.clearCheckpoint()
        root.lastCheckpointMs = 0
      }
    } else if (running) {
      // Refresh on a 30-second cadence, and immediately when a new phase
      // starts, so a hard power-off loses at most roughly 30 seconds.
      if (resumable && remaining > 0
        && (phase !== root.lastPhase || Date.now() - root.lastCheckpointMs >= 30000))
        root.saveCheckpoint()
    } else if (resumable && remaining > 0) {
      if (root.lastRunning) {
        // Pause freezes the exact remaining time.
        root.saveCheckpoint()
      } else if (phase !== root.lastPhase
        || pomodoro.completedFocusSessions !== root.lastCompleted
        || remaining > root.lastRemaining
        // Reset may leave an already-full phase unchanged; a saved checkpoint
        // proves there was progress to discard.
        || (focusLog.checkpoint !== null
          && remaining >= pomodoro.durationForPhase(phase) * 60)) {
        // Reset (or a fresh phase prepared while paused) discards the old checkpoint.
        focusLog.clearCheckpoint()
        root.lastCheckpointMs = 0
      }
    }
    root.rememberPomodoro()
  }

  Connections {
    target: focusLog

    function onCheckpointLoaded(snapshot) {
      if (!snapshot) {
        root.rememberPomodoro()
        return
      }
      root.restoringCheckpoint = true
      pomodoro.restoreSnapshot(snapshot.phase, snapshot.remainingSeconds,
                               snapshot.completedFocusSessions)
      root.rememberPomodoro()
      root.lastCheckpointMs = Date.now()
      root.restoringCheckpoint = false
    }
  }

  // Sampling once a second keeps pause/reset detection outside the engines.
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.checkpointTick()
  }

  // Test seams: drive deadline machines without waiting through a long cycle.
  function debugResetAll() {
    pomodoro.reset()
    countdown.setPreset(5)
    stopwatch.reset()
    root.debugEvents = []
  }
  function debugAdvancePhase() { pomodoro.advance() }
  function debugSetTimerPreset(minutes) { return countdown.setPreset(minutes) }
  function debugSetCustomMinutes(minutes) { return countdown.setCustomMinutes(minutes) }
  function debugExpireTimer() { countdown.complete() }
  // Redeliver a completion event verbatim to verify idempotent recording.
  function debugRedeliverFocus(payload) {
    var event = JSON.parse(payload)
    root.focusSessionCompleted(event.sessionId, event.durationMinutes, event.timestamp)
  }
  // Re-run the load path without restarting the shell; restore is observed
  // through state() JSON, never the QML visual tree.
  function debugRestoreCheckpoint() { focusLog.loadCheckpoint() }

  Component.onCompleted: root.rememberPomodoro()
}

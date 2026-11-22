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
}

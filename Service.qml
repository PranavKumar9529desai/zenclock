pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import Quickshell
import "timer-policy.js" as TimerPolicy

// Deep module: owns every timer state machine and the domain event seam.
// The shell loads this service once for the enabled plugin and keeps it alive,
// so deadlines and audio cues keep advancing while the overlay is dismissed.
// The overlay is only a view of this state.
Item {
  id: root

  readonly property alias pomodoroEngine: pomodoro
  readonly property alias timerEngine: countdown
  readonly property alias stopwatchEngine: stopwatch

  // ADR 0002 adapter seam: the default is the explicit no-op adapter below;
  // the recording adapter is selected at this same seam on startup. Tests can
  // select a test recording adapter through debugSelectFocusLogAdapter()
  // without editing this file.
  property var focusLog: noopFocusLog

  // V1 forwards events only. V2 connects a concrete database adapter to these
  // signals; there is no sink object and no in-memory analytics store here.
  signal focusSessionCompleted(string sessionId, int durationMinutes, real timestamp)
  signal cycleFinished(string cycleId, real timestamp)
  signal countdownCompleted(int durationMinutes, real timestamp)

  // Checkpoint observation lives here at the service seam: engines and views
  // stay unchanged except for PomodoroEngine.restoreSnapshot (ADR 0003).
  property bool restoringCheckpoint: false
  // Reset while running must synchronously drop the "should save" state. A
  // full-duration phase after Reset is not progress, and must not be saved by
  // the next 1-second tick while the async clear is still in flight.
  property bool checkpointSuppressed: false
  property string lastPhase: ""
  property int lastRemaining: -1
  property int lastCompleted: -1
  property bool lastRunning: false
  property real lastCheckpointMs: 0

  // Test-only capture, disabled by default, so production V1 keeps no history.
  property bool debugEventCapture: false
  property var debugEvents: []
  // Test-only count of requested audio cues (observed at the event seam, with
  // no engine changes): lets the degradation test prove cues still fire.
  property int debugCueTotal: 0

  // True for a paused, partially elapsed phase in any active phase, including
  // a restored Long Break. The view derives its "Resume" label from this same
  // pure policy; state() JSON exposes it without reading the visual tree.
  readonly property bool pomodoroPartiallyElapsed: TimerPolicy.isPartiallyElapsed(
    pomodoro.phase, pomodoro.remainingSeconds,
    pomodoro.focusMinutes, pomodoro.shortBreakMinutes, pomodoro.longBreakMinutes)

  function debugEventsJson() { return JSON.stringify(root.debugEvents) }
  function clearDebugEvents() { root.debugEvents = [] }
  function debugCueCount() { return root.debugCueTotal }

  PomodoroEngine { id: pomodoro }
  TimerEngine { id: countdown }
  StopwatchEngine { id: stopwatch }

  // The no-op adapter is the ADR 0002 default: it satisfies the whole seam
  // (signals, state JSON and calls) but records nothing.
  QtObject {
    id: noopFocusLog
    signal checkpointLoaded(var snapshot)
    property var checkpoint: null
    function recordFocus(sessionId, durationMinutes, timestamp) {}
    function recordCycle(cycleId, timestamp) {}
    function recordCountdown(durationMinutes, timestamp) {}
    function saveCheckpoint(phase, remainingSeconds, sessionNumber, completedFocusSessions) {}
    function loadCheckpoint() {}
    function clearCheckpoint() {}
    function stateJson() {
      return JSON.stringify({
        path: "", schemaVersion: 0, status: "noop",
        statusReason: "no recording adapter selected", journalMode: "",
        counts: { focus: 0, cycle: 0, countdown: 0 }, checkpoint: null
      })
    }
  }

  // V2: the concrete recording adapter at the seam. Its database path is fixed
  // by FocusLog.qml; there is no setting and no path mutator.
  FocusLog { id: productionFocusLog }

  // Test recording adapter: the same component constructed with an isolated
  // path. The test selects it through the seam, so production code stays clean.
  QtObject { id: testAdapterConfig; property string path: "" }
  Loader {
    id: testFocusLogLoader
    active: false
    sourceComponent: Component {
      FocusLog { dbPath: testAdapterConfig.path }
    }
    onLoaded: root.focusLog = item
  }

  function selectFocusLogAdapter(name, path) {
    if (name === "noop" || name === "none") {
      testFocusLogLoader.active = false
      root.focusLog = noopFocusLog
      return
    }
    if (name === "test") {
      testAdapterConfig.path = path || ""
      testFocusLogLoader.active = true
      root.focusLog = testFocusLogLoader.item
      return
    }
    // "production" / "recording": the default, with no test path involved.
    testFocusLogLoader.active = false
    root.focusLog = productionFocusLog
  }
  // Test seam: one string argument survives shell IPC. "test:<path>" selects
  // the isolated test adapter; "production" / "noop" need no path.
  function debugSelectFocusLogAdapter(spec) {
    var name = spec || "production"
    var path = ""
    var colon = name.indexOf(":")
    if (colon > 0) {
      path = name.substring(colon + 1)
      name = name.substring(0, colon)
    }
    root.selectFocusLogAdapter(name, path)
  }

  // Connect at the signal itself so every delivery is recorded, including a
  // redelivered event (INSERT OR IGNORE in the helper makes that idempotent).
  Connections {
    target: root

    function onFocusSessionCompleted(sessionId, durationMinutes, timestamp) {
      if (root.focusLog) root.focusLog.recordFocus(sessionId, durationMinutes, timestamp)
    }

    function onCycleFinished(cycleId, timestamp) {
      if (root.focusLog) root.focusLog.recordCycle(cycleId, timestamp)
    }

    function onCountdownCompleted(durationMinutes, timestamp) {
      if (root.focusLog) root.focusLog.recordCountdown(durationMinutes, timestamp)
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

    function onRunningChanged() {
      if (root.restoringCheckpoint) return
      if (TimerPolicy.resetWhileRunning(root.lastRunning, pomodoro.running,
            pomodoro.remainingSeconds, pomodoro.durationForPhase(pomodoro.phase))) {
        root.markCheckpointReset()
      } else if (pomodoro.running) {
        // Play (or a phase that begins running) is the new phase: resume the
        // normal 30-second checkpoint cadence.
        root.checkpointSuppressed = false
        root.rememberPomodoro()
      }
    }

    // reset() sets running=false before it refills remainingSeconds, so the
    // full-phase signal usually arrives here, one property change later.
    function onRemainingSecondsChanged() {
      if (root.restoringCheckpoint || pomodoro.running || !root.lastRunning) return
      if (TimerPolicy.isFullPhase(pomodoro.remainingSeconds,
            pomodoro.durationForPhase(pomodoro.phase)))
        root.markCheckpointReset()
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

  // One cue counter for all engines, connected once instead of duplicated
  // onCueRequested handlers. The engines' own cue dispatch is untouched.
  function countCue() { root.debugCueTotal++ }

  function rememberPomodoro() {
    root.lastPhase = pomodoro.phase
    root.lastRemaining = pomodoro.remainingSeconds
    root.lastCompleted = pomodoro.completedFocusSessions
    root.lastRunning = pomodoro.running
  }

  function clearCheckpoint() {
    if (root.focusLog) root.focusLog.clearCheckpoint()
  }

  // Reset, unlike pause: synchronously drop the should-save state and suppress
  // checkpoint writes until a new phase actually starts. The async clear
  // response must not be load-bearing for correctness.
  function markCheckpointReset() {
    root.checkpointSuppressed = true
    root.lastRunning = false
    root.lastCheckpointMs = 0
    root.clearCheckpoint()
    root.rememberPomodoro()
  }

  function saveCheckpoint() {
    if (!root.focusLog) return
    root.focusLog.saveCheckpoint(pomodoro.phase, pomodoro.remainingSeconds,
                                 pomodoro.sessionNumber, pomodoro.completedFocusSessions)
    root.lastCheckpointMs = Date.now()
  }

  function checkpointTick() {
    if (root.restoringCheckpoint || root.checkpointSuppressed) return
    var phase = pomodoro.phase
    var resumable = phase === "focus" || phase === "shortBreak" || phase === "longBreak"
    var running = pomodoro.running
    var remaining = pomodoro.remainingSeconds

    if (phase === "cycleComplete") {
      // A halted cycle has no interrupted phase to resume.
      if (root.lastPhase !== "cycleComplete") {
        root.clearCheckpoint()
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
        || (root.focusLog && root.focusLog.checkpoint !== null
          && remaining >= pomodoro.durationForPhase(phase) * 60)) {
        // Reset (or a fresh phase prepared while paused) discards the old checkpoint.
        root.clearCheckpoint()
        root.lastCheckpointMs = 0
      }
    }
    root.rememberPomodoro()
  }

  Connections {
    target: root.focusLog

    function onCheckpointLoaded(snapshot) {
      if (!snapshot) {
        root.rememberPomodoro()
        return
      }
      root.restoringCheckpoint = true
      pomodoro.restoreSnapshot(snapshot.phase, snapshot.remainingSeconds,
                               snapshot.sessionNumber, snapshot.completedFocusSessions)
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
    // Clear the flag before reset(): a reset while running must be allowed to
    // set its own suppression rather than having it erased here.
    root.checkpointSuppressed = false
    // Full test-seam reset from V1; the checkpoint handler observes its
    // running/remaining transitions and re-suppresses writes as needed.
    pomodoro.resetAll()
    countdown.setPreset(5)
    stopwatch.reset()
    root.debugEvents = []
    root.debugCueTotal = 0
  }
  function debugAdvancePhase() { pomodoro.advance() }
  function debugSetTimerPreset(minutes) { return countdown.setPreset(minutes) }
  function debugSetCustomMinutes(minutes) { return countdown.setCustomMinutes(minutes) }
  function debugExpireTimer() { countdown.complete() }
  // Redeliver one completion event verbatim; kind selects the service seam.
  function debugRedeliver(kind, payload) {
    var event = JSON.parse(payload)
    if (kind === "focus")
      root.focusSessionCompleted(event.sessionId, event.durationMinutes, event.timestamp)
    else if (kind === "cycle")
      root.cycleFinished(event.cycleId, event.timestamp)
    else if (kind === "countdown")
      root.countdownCompleted(event.durationMinutes, event.timestamp)
  }
  function debugRedeliverFocus(payload) { root.debugRedeliver("focus", payload) }
  function debugRedeliverCycle(payload) { root.debugRedeliver("cycle", payload) }
  function debugRedeliverCountdown(payload) { root.debugRedeliver("countdown", payload) }
  // Re-run the load path without restarting the shell; restore is observed
  // through state() JSON, never the QML visual tree.
  function debugRestoreCheckpoint() { if (root.focusLog) root.focusLog.loadCheckpoint() }

  Component.onCompleted: {
    // One cue counter for every engine; no engine or view was changed.
    pomodoro.cueRequested.connect(root.countCue)
    countdown.cueRequested.connect(root.countCue)
    root.selectFocusLogAdapter("production", "")
    root.rememberPomodoro()
  }
}

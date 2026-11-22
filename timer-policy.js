// Pure timer/checkpoint decisions shared by the QML service and view.
//
// No Qt or Quickshell dependency: QML imports this file as TimerPolicy and the
// unit tests require it directly from node. Keeping the decisions here makes
// the Reset race and the "Resume" label derivation testable without a shell.

function isFullPhase(remainingSeconds, durationMinutes) {
  return remainingSeconds >= durationMinutes * 60
}

// Reset while a phase runs jumps remaining back to a full phase; a pause
// leaves it partially elapsed. Used to discard the "should save" state
// synchronously instead of waiting for an async clear_checkpoint response.
function resetWhileRunning(lastRunning, running, remainingSeconds, durationMinutes) {
  return lastRunning === true && running === false && isFullPhase(remainingSeconds, durationMinutes)
}

// A paused, partially elapsed phase resumes with the primary button's
// "Resume" label. Every active phase is checked, not just Focus Session.
function isPartiallyElapsed(phase, remainingSeconds, focusMinutes, shortBreakMinutes, longBreakMinutes) {
  if (phase === "focus") return remainingSeconds < focusMinutes * 60
  if (phase === "shortBreak") return remainingSeconds < shortBreakMinutes * 60
  if (phase === "longBreak") return remainingSeconds < longBreakMinutes * 60
  return false
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    isFullPhase: isFullPhase,
    resetWhileRunning: resetWhileRunning,
    isPartiallyElapsed: isPartiallyElapsed
  }
}

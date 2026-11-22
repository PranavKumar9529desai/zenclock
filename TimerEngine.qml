pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// UI-free countdown state machine. Lives under the always-loaded overlay root
// (keepLoaded: true), so its deadline keeps advancing even while the overlay
// is dismissed and the completion cue still fires on time.
Item {
  id: root

  // Quick presets and the accepted range for custom durations (minutes).
  property var presets: [5, 15, 25, 45, 60]
  property int minMinutes: 1
  property int maxMinutes: 180

  property int customMinutes: 10
  property bool customActive: false      // true when the current run uses a custom duration
  property int durationMinutes: 5
  property int remainingSeconds: 5 * 60
  property bool running: false
  property real deadlineMs: 0            // wall-clock deadline for the current run

  readonly property int durationSeconds: root.durationMinutes * 60
  readonly property string formattedTime: formatSeconds(root.remainingSeconds)

  // Domain event seam for the future SQLite sink (Ticket 5). The timestamp is
  // Unix epoch milliseconds (Date.now()); durationMinutes is the configured
  // length of the run that just elapsed. No storage / analytics here.
  signal countdownCompleted(int durationMinutes, real timestamp)
  // Cue names: "complete" (countdown reached 00:00). Audio-only by design:
  // never notify-send / desktop popups. Ticket 5 can also listen here.
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

  // Selecting a preset configures a fresh, paused countdown.
  function setPreset(minutes) {
    var value = Math.floor(Number(minutes))
    if (!isFinite(value) || value < root.minMinutes || value > root.maxMinutes) return false
    root.customActive = false
    root.durationMinutes = value
    root.remainingSeconds = value * 60
    root.running = false
    root.deadlineMs = 0
    return true
  }

  // Custom durations are integer minutes within [minMinutes, maxMinutes].
  // Invalid input is rejected without disturbing the current run.
  function setCustomMinutes(minutes) {
    var value = Number(minutes)
    if (!isFinite(value) || value !== Math.floor(value)) return false
    if (value < root.minMinutes || value > root.maxMinutes) return false
    root.customMinutes = value
    root.customActive = true
    root.durationMinutes = value
    root.remainingSeconds = value * 60
    root.running = false
    root.deadlineMs = 0
    return true
  }

  function start() {
    if (root.running) return
    if (root.remainingSeconds <= 0) root.remainingSeconds = root.durationSeconds
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
    if (root.running) root.pause()
    else root.start()
  }

  // Reset restores the full configured duration and pauses.
  function reset() {
    root.running = false
    root.deadlineMs = 0
    root.remainingSeconds = root.durationSeconds
  }

  // Recompute from the wall clock, never decrement a counter, so time spent
  // with the overlay hidden (or delayed ticks) never cause drift.
  function refreshRemaining() {
    if (!root.running || root.deadlineMs <= 0) return
    var left = Math.max(0, Math.ceil((root.deadlineMs - Date.now()) / 1000))
    root.remainingSeconds = left
    if (left === 0) root.complete()
  }

  function complete() {
    root.running = false
    root.deadlineMs = 0
    root.remainingSeconds = 0
    var nowMs = Date.now()
    root.countdownCompleted(root.durationMinutes, nowMs)
    root.cueRequested("complete")
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.running
    onTriggered: root.refreshRemaining()
  }
}

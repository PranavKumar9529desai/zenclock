pragma ComponentBehavior: Bound
import QtQuick

// UI-free count-up state machine. Lives under the always-loaded overlay root
// (keepLoaded: true), so elapsed time stays accurate while the overlay is
// dismissed. No cues: a stopwatch never chimes on its own.
Item {
  id: root

  property bool running: false
  property real accumulatedMs: 0   // elapsed before the current run started
  property real startedAtMs: 0     // Date.now() at the start of the current run
  property real elapsedMs: 0

  readonly property int elapsedSeconds: Math.floor(root.elapsedMs / 1000)
  readonly property string formattedTime: formatElapsed(root.elapsedSeconds)

  function formatElapsed(totalSeconds) {
    var s = Math.max(0, Math.floor(totalSeconds))
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var r = s % 60
    var mm = (m < 10 ? "0" : "") + m
    var ss = (r < 10 ? "0" : "") + r
    // Switch to HH:MM:SS only once an hour has elapsed.
    return h > 0 ? ((h < 10 ? "0" : "") + h + ":" + mm + ":" + ss) : (mm + ":" + ss)
  }

  // Always derive from the wall clock rather than adding tick intervals, so
  // hidden time and delayed ticks cannot introduce drift.
  function refresh() {
    if (!root.running) return
    root.elapsedMs = root.accumulatedMs + Math.max(0, Date.now() - root.startedAtMs)
  }

  function start() {
    if (root.running) return
    root.startedAtMs = Date.now()
    root.running = true
  }

  function pause() {
    if (!root.running) return
    root.accumulatedMs += Math.max(0, Date.now() - root.startedAtMs)
    root.startedAtMs = 0
    root.elapsedMs = root.accumulatedMs
    root.running = false
  }

  function toggle() {
    if (root.running) root.pause()
    else root.start()
  }

  function reset() {
    root.running = false
    root.startedAtMs = 0
    root.accumulatedMs = 0
    root.elapsedMs = 0
  }

  Timer {
    interval: 100
    repeat: true
    running: root.running
    onTriggered: root.refresh()
  }
}

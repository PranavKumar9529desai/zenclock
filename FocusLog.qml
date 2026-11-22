pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// The one adapter at the domain event seam (ADR 0002). It owns the Focus Log
// file, the write helper process and the observable storage status. Engines and
// views are untouched: callers only emit the existing completion signal.
Item {
  id: root

  // Fixed for this adapter's lifetime by the published schema: there is no
  // setting and no mutator. Tests get isolation by selecting the test adapter
  // at the Service seam, which constructs its own instance with its own path.
  property string dbPath: Quickshell.statePath("zenclock/focus-log.sqlite3")
  // The only schema version this adapter understands. A database reporting
  // anything else is degraded, never published as a readable schemaVersion.
  readonly property int supportedSchemaVersion: 1
  property int schemaVersion: root.supportedSchemaVersion

  property string status: "initializing"
  property string statusReason: ""
  property string journalMode: ""
  property int focusRecordCount: 0
  property int cycleRecordCount: 0
  property int countdownRecordCount: 0
  property var checkpoint: null

  // Emitted once per load request, with null when no checkpoint was saved.
  // The service uses it to restore the Pomodoro engine in a paused state.
  signal checkpointLoaded(var snapshot)

  // Resolved relative to this file so the helper travels with the plugin.
  readonly property string helperPath: {
    var url = Qt.resolvedUrl("focus_log_helper.py").toString()
    return url.replace(/^file:\/\//, "").replace(/%20/g, " ")
  }

  property var pending: []

  function send(command) {
    if (!helper.running) {
      root.pending.push(command)
      return
    }
    helper.write(JSON.stringify(command) + "\n")
  }

  function flushPending() {
    var queued = root.pending
    root.pending = []
    for (var i = 0; i < queued.length; i++)
      helper.write(JSON.stringify(queued[i]) + "\n")
  }

  function applyResponse(response) {
    if (!response || response.ok !== true) {
      // Storage trouble is a no-op degradation, never an unhandled failure:
      // record the reason, report it in state(), and leave the log alone.
      var reason = (response && response.error) || "storage unavailable"
      root.status = (response && response.status) || "degraded"
      root.statusReason = reason
      console.warn("Focus Log storage degraded:", reason)
      return
    }
    root.status = response.status || "ok"
    root.statusReason = ""
    root.journalMode = response.journalMode || ""
    if (response.version) {
      if (response.version !== root.supportedSchemaVersion) {
        var versionReason = "unrecognized Focus Log schema version " + response.version
        root.status = "degraded"
        root.statusReason = versionReason
        console.warn("Focus Log:", versionReason)
        return
      }
      root.schemaVersion = response.version
    }
    if (response.counts) {
      root.focusRecordCount = response.counts.focus || 0
      root.cycleRecordCount = response.counts.cycle || 0
      root.countdownRecordCount = response.counts.countdown || 0
    }
    if ("checkpoint" in response) root.checkpoint = response.checkpoint
    if (response.op === "load_checkpoint")
      root.checkpointLoaded(response.checkpoint || null)
  }

  // Writes one idempotent Focus Record for a completed Focus Session.
  function recordFocus(sessionId, durationMinutes, timestamp) {
    root.send({
      op: "record_focus",
      path: root.dbPath,
      id: sessionId,
      durationMinutes: durationMinutes,
      timestamp: timestamp
    })
  }

  // Checkpoint writes go through the same one-row helper. Pause and the 30s
  // cadence both call saveCheckpoint; Reset calls clearCheckpoint.
  function saveCheckpoint(phase, remainingSeconds, sessionNumber, completedFocusSessions) {
    root.send({
      op: "save_checkpoint",
      path: root.dbPath,
      phase: phase,
      remainingSeconds: remainingSeconds,
      sessionNumber: sessionNumber,
      completedFocusSessions: completedFocusSessions
    })
  }

  function loadCheckpoint() { root.send({ op: "load_checkpoint", path: root.dbPath }) }
  function clearCheckpoint() { root.send({ op: "clear_checkpoint", path: root.dbPath }) }

  // Writes one idempotent Cycle Record for a completed Pomodoro Cycle.
  function recordCycle(cycleId, timestamp) {
    root.send({
      op: "record_cycle",
      path: root.dbPath,
      id: cycleId,
      timestamp: timestamp
    })
  }

  // Writes one idempotent Countdown Record for a completed Timer countdown.
  // The helper derives the deterministic key from timestamp and duration.
  function recordCountdown(durationMinutes, timestamp) {
    root.send({
      op: "record_countdown",
      path: root.dbPath,
      durationMinutes: durationMinutes,
      timestamp: timestamp
    })
  }

  function refresh() { root.send({ op: "status", path: root.dbPath }) }

  // One JSON state payload for the whole adapter, consumed verbatim by
  // Overlay.state() so state() and the adapter cannot drift apart.
  function stateJson() {
    return JSON.stringify({
      path: root.dbPath,
      schemaVersion: root.status === "ok" ? root.schemaVersion : 0,
      status: root.status,
      statusReason: root.statusReason,
      journalMode: root.journalMode,
      counts: {
        focus: root.focusRecordCount,
        cycle: root.cycleRecordCount,
        countdown: root.countdownRecordCount
      },
      // Checkpoint position (phase, remaining seconds, session number and
      // saved-at) is observable state, not a visual-tree detail.
      checkpoint: root.checkpoint
    })
  }

  Process {
    id: helper
    command: ["/usr/bin/python3", root.helperPath]
    stdinEnabled: true

    stdout: SplitParser {
      onRead: function(line) {
        var response
        try { response = JSON.parse(line) } catch (e) { return }
        root.applyResponse(response)
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim()) console.warn("Focus Log helper:", text.trim())
      }
    }

    onRunningChanged: if (helper.running) root.flushPending()
    // A nonzero (or unexpected) helper exit is itself a failed write: degrade
    // with a reason rather than letting the exception escape to the overlay.
    onExited: function(exitCode) {
      var code = (typeof exitCode === "number") ? exitCode : "?"
      var reason = "Focus Log helper exited (" + code + ")"
      root.status = "degraded"
      root.statusReason = reason
      console.warn(reason)
    }
  }

  Component.onCompleted: {
    // The helper creates the schema on first use, so init, load and an early
    // record are all safe; send() queues them until the process starts.
    root.send({ op: "init", path: root.dbPath })
    root.loadCheckpoint()
    helper.running = true
  }
}

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// The one adapter at the domain event seam (ADR 0002). It owns the Focus Log
// file, the write helper process and the observable storage status. Engines and
// views are untouched: callers only emit the existing completion signal.
Item {
  id: root

  readonly property string dbPath: Quickshell.statePath("zenclock/focus-log.sqlite3")
  property int schemaVersion: 1

  property string status: "initializing"
  property string journalMode: ""
  property int focusRecordCount: 0
  property int cycleRecordCount: 0
  property int countdownRecordCount: 0

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
      root.status = "error"
      return
    }
    root.status = response.status || "ok"
    root.journalMode = response.journalMode || ""
    if (response.version) root.schemaVersion = response.version
    if (response.counts) {
      root.focusRecordCount = response.counts.focus || 0
      root.cycleRecordCount = response.counts.cycle || 0
      root.countdownRecordCount = response.counts.countdown || 0
    }
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

  function stateJson() {
    return JSON.stringify({
      path: root.dbPath,
      schemaVersion: root.schemaVersion,
      status: root.status,
      journalMode: root.journalMode,
      counts: {
        focus: root.focusRecordCount,
        cycle: root.cycleRecordCount,
        countdown: root.countdownRecordCount
      }
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
    onExited: root.status = "error"
  }

  Component.onCompleted: {
    // The helper creates the schema on first use, so an init command and an
    // early record are both safe; send() queues them until the process starts.
    root.send({ op: "init", path: root.dbPath })
    helper.running = true
  }
}

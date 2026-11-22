pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  // Injected by the Omarchy shell's overlay loader.
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string mode: "clock" // "clock" | "pomodoro" | "timer" | "stopwatch"
  // Owner-controlled seam: when Zen Inactivity lands, it binds this to its
  // zenActive state so every mode's secondary HUD fades, leaving only the
  // primary digits visible.
  property bool hudFaded: false

  // Clock state. The clock stays live while hidden so re-summoning never
  // shows a stale time.
  property bool hour12: true
  property var now: new Date()
  property string zoneName: ""
  property string zoneAbbr: ""
  property var targetScreen: Quickshell.screens[0] || null

  // Always-loaded state machines: their deadline timers keep advancing while
  // the overlay is dismissed (manifest keepLoaded: true), so a countdown still
  // chimes and a stopwatch stays accurate in the background.
  PomodoroEngine { id: pomodoroEngine }
  TimerEngine { id: timerEngine }
  StopwatchEngine { id: stopwatchEngine }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function pad2(value) {
    var n = Math.floor(value)
    return (n < 10 ? "0" : "") + n
  }

  function offsetLabel(date) {
    var minutes = -date.getTimezoneOffset()
    var sign = minutes < 0 ? "-" : "+"
    return sign + pad2(Math.abs(minutes) / 60) + ":" + pad2(Math.abs(minutes) % 60)
  }

  readonly property int hours: root.now.getHours()
  readonly property int minutes: root.now.getMinutes()
  readonly property int seconds: root.now.getSeconds()
  readonly property string clockText: root.hour12
    ? (root.pad2(root.hours % 12 === 0 ? 12 : root.hours % 12) + ":" + root.pad2(root.minutes))
    : (root.pad2(root.hours) + ":" + root.pad2(root.minutes))
  readonly property string secondsText: ":" + root.pad2(root.seconds)
  readonly property string ampmText: root.hours < 12 ? "AM" : "PM"
  readonly property string dateText: Qt.formatDate(root.now, "dddd, d MMMM yyyy")
  readonly property string timezoneText: root.zoneName
    ? root.zoneName + " • " + root.zoneAbbr + " (UTC" + root.offsetLabel(root.now) + ")"
    : ""

  function open(payload) {
    root.opened = true
    monitorProbe.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "pranav.zenclock")
  }

  function toggleFormat() {
    root.hour12 = !root.hour12
  }

  function setMode(nextMode) {
    if (nextMode !== "clock" && nextMode !== "pomodoro"
      && nextMode !== "timer" && nextMode !== "stopwatch") return
    root.mode = nextMode
    // A pill click should leave Space / R / 1-4 live, even after the Timer
    // view's custom-minutes field had focus.
    keyCatcher.forceActiveFocus()
  }

  function state() {
    return JSON.stringify({
      opened: root.opened,
      format: root.hour12 ? "12h" : "24h",
      time: root.clockText + root.secondsText + (root.hour12 ? " " + root.ampmText : ""),
      timezone: root.timezoneText,
      mode: root.mode,
      pomodoro: root.mode === "pomodoro" ? {
        phase: pomodoroEngine.phase,
        remaining: pomodoroEngine.formattedTime,
        session: pomodoroEngine.sessionNumber,
        running: pomodoroEngine.running,
        cycleHalted: pomodoroEngine.cycleHalted
      } : null,
      timer: root.mode === "timer" ? {
        remaining: timerEngine.formattedTime,
        remainingSeconds: timerEngine.remainingSeconds,
        running: timerEngine.running,
        duration: timerEngine.durationMinutes,
        custom: timerEngine.customActive
      } : null,
      stopwatch: root.mode === "stopwatch" ? {
        elapsed: stopwatchEngine.formattedTime,
        elapsedSeconds: stopwatchEngine.elapsedSeconds,
        elapsedMilliseconds: stopwatchEngine.elapsedMs,
        duration: stopwatchEngine.elapsedSeconds,
        running: stopwatchEngine.running
      } : null
    })
  }

  Component.onCompleted: timezoneProbe.running = true

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.now = new Date()
  }

  // The Timezone Badge reads the system zone once at load; the UTC offset is
  // recomputed from the live clock so daylight-saving changes are reflected.
  Process {
    id: timezoneProbe
    command: ["bash", "-c", "readlink -f /etc/localtime 2>/dev/null; date +%Z"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        var path = lines[0] || ""
        var marker = "/zoneinfo/"
        var at = path.indexOf(marker)
        root.zoneName = at >= 0 ? path.substring(at + marker.length) : path
        root.zoneAbbr = lines[1] || ""
      }
    }
  }

  // Land the overlay on the monitor that currently has Hyprland focus.
  Process {
    id: monitorProbe
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        var monitors = []
        try { monitors = JSON.parse(text) } catch (e) { monitors = [] }
        var focused = null
        for (var i = 0; i < monitors.length; i++)
          if (monitors[i].focused === true) focused = monitors[i]
        var match = null
        if (focused) {
          for (var j = 0; j < Quickshell.screens.length; j++)
            if (Quickshell.screens[j].name === focused.name) match = Quickshell.screens[j]
        }
        root.targetScreen = match || Quickshell.screens[0] || null
      }
    }
  }

  PanelWindow {
    id: panel

    screen: root.targetScreen
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "#08080a"

    WlrLayershell.namespace: "zenclock"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        // Dismiss always wins, even while typing a custom duration.
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
          return
        }
        // While the custom-minutes field has focus it owns its keystrokes, so
        // typing digits never switches modes or toggles the countdown.
        if (root.mode === "timer" && timerView.textEntryActive) return

        if (event.key === Qt.Key_T) {
          root.toggleFormat()
          event.accepted = true
        } else if (event.key === Qt.Key_1) {
          root.setMode("clock")
          event.accepted = true
        } else if (event.key === Qt.Key_2) {
          root.setMode("pomodoro")
          event.accepted = true
        } else if (event.key === Qt.Key_3) {
          root.setMode("timer")
          event.accepted = true
        } else if (event.key === Qt.Key_4) {
          root.setMode("stopwatch")
          event.accepted = true
        } else if (root.mode === "pomodoro" && event.key === Qt.Key_Space) {
          pomodoroEngine.toggle()
          event.accepted = true
        } else if (root.mode === "pomodoro" && event.key === Qt.Key_R) {
          pomodoroEngine.reset()
          event.accepted = true
        } else if (root.mode === "timer" && event.key === Qt.Key_Space) {
          timerEngine.toggle()
          event.accepted = true
        } else if (root.mode === "timer" && event.key === Qt.Key_R) {
          timerEngine.reset()
          event.accepted = true
        } else if (root.mode === "stopwatch" && event.key === Qt.Key_Space) {
          stopwatchEngine.toggle()
          event.accepted = true
        } else if (root.mode === "stopwatch" && event.key === Qt.Key_R) {
          stopwatchEngine.reset()
          event.accepted = true
        }
      }

      // Secondary HUD elements. Kept in one group so Zen Inactivity can fade
      // them as a unit without touching the primary time display.
      Item {
        id: hud
        anchors.fill: parent

        Row {
          anchors { top: parent.top; left: parent.left; topMargin: 42; leftMargin: 48 }
          spacing: 12

          PlainText {
            anchors.verticalCenter: parent.verticalCenter
            text: "◷"
            font.pixelSize: 20
            font.family: Style.font.family
            color: "#7dd3fc"
          }
          PlainText {
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("title")
            font.pixelSize: 16
            font.letterSpacing: 3
            font.family: Style.font.family
            color: "#8a8a96"
          }
        }

        // Floating mode selector: Clock (1), Pomodoro (2), Timer (3),
        // Stopwatch (4).
        Row {
          anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 34 }
          spacing: 10

          Rectangle {
            id: clockPill
            property bool hovered: false
            radius: 999
            color: root.mode === "clock" ? "#1b2a33" : (clockPill.hovered ? "#1e1e26" : "#141419")
            border.color: root.mode === "clock" ? "#7dd3fc" : "#2a2a34"
            border.width: 1
            implicitWidth: clockPillLabel.implicitWidth + 32
            implicitHeight: clockPillLabel.implicitHeight + 14

            Behavior on color {
              ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
            }

            PlainText {
              id: clockPillLabel
              anchors.centerIn: parent
              text: strings.t("pill.clock")
              font.pixelSize: 13
              font.letterSpacing: 2
              font.family: Style.font.family
              color: root.mode === "clock" ? "#7dd3fc" : "#8a8a96"
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: clockPill.hovered = true
              onExited: clockPill.hovered = false
              onClicked: root.setMode("clock")
            }
          }

          Rectangle {
            id: pomodoroPill
            property bool hovered: false
            radius: 999
            color: root.mode === "pomodoro" ? "#1b2a33" : (pomodoroPill.hovered ? "#1e1e26" : "#141419")
            border.color: root.mode === "pomodoro" ? "#7dd3fc" : "#2a2a34"
            border.width: 1
            implicitWidth: pomodoroPillLabel.implicitWidth + 32
            implicitHeight: pomodoroPillLabel.implicitHeight + 14

            Behavior on color {
              ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
            }

            PlainText {
              id: pomodoroPillLabel
              anchors.centerIn: parent
              text: strings.t("pill.pomodoro")
              font.pixelSize: 13
              font.letterSpacing: 2
              font.family: Style.font.family
              color: root.mode === "pomodoro" ? "#7dd3fc" : "#8a8a96"
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: pomodoroPill.hovered = true
              onExited: pomodoroPill.hovered = false
              onClicked: root.setMode("pomodoro")
            }
          }

          Rectangle {
            id: timerPill
            property bool hovered: false
            radius: 999
            color: root.mode === "timer" ? "#1b2a33" : (timerPill.hovered ? "#1e1e26" : "#141419")
            border.color: root.mode === "timer" ? "#7dd3fc" : "#2a2a34"
            border.width: 1
            implicitWidth: timerPillLabel.implicitWidth + 32
            implicitHeight: timerPillLabel.implicitHeight + 14

            Behavior on color {
              ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
            }

            PlainText {
              id: timerPillLabel
              anchors.centerIn: parent
              text: strings.t("pill.timer")
              font.pixelSize: 13
              font.letterSpacing: 2
              font.family: Style.font.family
              color: root.mode === "timer" ? "#7dd3fc" : "#8a8a96"
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: timerPill.hovered = true
              onExited: timerPill.hovered = false
              onClicked: root.setMode("timer")
            }
          }

          Rectangle {
            id: stopwatchPill
            property bool hovered: false
            radius: 999
            color: root.mode === "stopwatch" ? "#1b2a33" : (stopwatchPill.hovered ? "#1e1e26" : "#141419")
            border.color: root.mode === "stopwatch" ? "#7dd3fc" : "#2a2a34"
            border.width: 1
            implicitWidth: stopwatchPillLabel.implicitWidth + 32
            implicitHeight: stopwatchPillLabel.implicitHeight + 14

            Behavior on color {
              ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
            }

            PlainText {
              id: stopwatchPillLabel
              anchors.centerIn: parent
              text: strings.t("pill.stopwatch")
              font.pixelSize: 13
              font.letterSpacing: 2
              font.family: Style.font.family
              color: root.mode === "stopwatch" ? "#7dd3fc" : "#8a8a96"
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: stopwatchPill.hovered = true
              onExited: stopwatchPill.hovered = false
              onClicked: root.setMode("stopwatch")
            }
          }
        }

        Rectangle {
          anchors { top: parent.top; right: parent.right; topMargin: 36; rightMargin: 48 }
          radius: 999
          color: "#141419"
          border.color: "#2a2a34"
          border.width: 1
          implicitWidth: zoneLabel.implicitWidth + 36
          implicitHeight: zoneLabel.implicitHeight + 18

          PlainText {
            id: zoneLabel
            anchors.centerIn: parent
            text: root.timezoneText
            font.pixelSize: 14
            font.family: Style.font.family
            color: "#b6b6c2"
          }
        }

        Row {
          anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 40 }
          spacing: 32

          PlainText {
            text: strings.t("hint.dismiss")
            font.pixelSize: 13
            font.letterSpacing: 2
            font.family: Style.font.family
            color: "#55555f"
          }
          PlainText {
            text: strings.t("hint.toggle")
            font.pixelSize: 13
            font.letterSpacing: 2
            font.family: Style.font.family
            color: "#55555f"
          }
          PlainText {
            text: strings.t("hint.format")
            font.pixelSize: 13
            font.letterSpacing: 2
            font.family: Style.font.family
            color: "#55555f"
          }
        }
      }

      Item {
        anchors.centerIn: parent
        visible: root.mode === "clock"
        width: clockColumn.implicitWidth
        height: clockColumn.implicitHeight

        Column {
          id: clockColumn
          anchors.centerIn: parent
          spacing: 18

          Row {
            id: clockRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            PlainText {
              id: clockLabel
              anchors.verticalCenter: parent.verticalCenter
              text: root.clockText
              font.pixelSize: Math.min(panel.width * 0.16, 280)
              font.weight: Font.Light
              font.family: Style.font.family
              color: "#f4f4f8"
            }
            PlainText {
              anchors.baseline: clockLabel.baseline
              text: root.secondsText
              font.pixelSize: clockLabel.font.pixelSize * 0.32
              font.weight: Font.Light
              font.family: Style.font.family
              color: "#7c7c8a"
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.hour12
              radius: 10
              color: "#141419"
              implicitWidth: ampmLabel.implicitWidth + 24
              implicitHeight: ampmLabel.implicitHeight + 14

              PlainText {
                id: ampmLabel
                anchors.centerIn: parent
                text: root.ampmText
                font.pixelSize: clockLabel.font.pixelSize * 0.18
                font.bold: true
                font.letterSpacing: 2
                font.family: Style.font.family
                color: "#7dd3fc"
              }
            }
          }

          PlainText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateText
            font.pixelSize: Math.max(18, Math.min(panel.width * 0.022, 34))
            font.weight: Font.Light
            font.family: Style.font.family
            color: "#9a9aa6"
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleFormat()
        }
      }

      PomodoroView {
        visible: root.mode === "pomodoro"
        anchors.fill: parent
        engine: pomodoroEngine
        hudFaded: root.hudFaded
      }

      TimerView {
        id: timerView
        visible: root.mode === "timer"
        anchors.fill: parent
        engine: timerEngine
        hudFaded: root.hudFaded
        onFocusRestored: keyCatcher.forceActiveFocus()
      }

      StopwatchView {
        visible: root.mode === "stopwatch"
        anchors.fill: parent
        engine: stopwatchEngine
        hudFaded: root.hudFaded
      }
    }
  }
}

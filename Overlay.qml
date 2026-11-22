pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  // Visual tokens live in one place; see ZenTheme.qml.
  ZenTheme { id: theme }

  // Injected by the Omarchy shell's overlay loader.
  property var shell: null
  property var manifest: null
  // The shell injects the plugin's service; fall back if the loader ran first.
  property var service: null
  property bool opened: false
  property bool openRequested: false
  property string mode: "clock" // "clock" | "pomodoro" | "timer" | "stopwatch"
  // Actions are suppressed while Zen is active and briefly after waking, so
  // revealing the HUD never silently triggers the control underneath.
  readonly property bool actionLocked: inactivity.zenActive || inactivity.justWoke
  property bool cueAvailable: true

  // Clock state. The clock stays live while hidden so re-summoning never
  // shows a stale time.
  property bool hour12: true
  property var now: new Date()
  property string zoneName: ""
  property string zoneAbbr: ""
  property var targetScreen: Quickshell.screens[0] || null

  // All timers live in Service.qml, which the shell keeps loaded even while
  // this overlay is hidden — that is what makes background ticking and chimes
  // reliable. This file only renders service state and forwards input.
  Timer {
    interval: 200
    repeat: true
    running: root.service === null
    onTriggered: {
      if (root.shell && typeof root.shell.serviceFor === "function"
        && root.manifest && root.manifest.id)
        root.service = root.shell.serviceFor(root.manifest.id)
    }
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  // Zen Inactivity: fades the secondary HUD and hides the cursor after idle.
  InactivityController {
    id: inactivity
    active: root.opened
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
  readonly property string dateText: Qt.formatDate(
    root.now, Qt.locale(Commons.I18n.formatLocale), "dddd, d MMMM yyyy")
  readonly property string timezoneText: root.zoneName
    ? root.zoneName + " · " + root.zoneAbbr + " (UTC" + root.offsetLabel(root.now) + ")"
    : ""
  readonly property string hintText: root.mode === "clock"
    ? strings.t("hint.clock") : strings.t("hint.active")

  // Only show the panel once the focused monitor is known, so it never flashes
  // on the previous screen or loses focus to a screen change after mapping.
  function open(payload) {
    root.openRequested = true
    monitorProbe.running = false
    monitorProbe.running = true
  }

  function finishOpen() {
    if (!root.openRequested || root.opened) return
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.openRequested = false
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && root.manifest && root.manifest.id && typeof root.shell.hide === "function")
      root.shell.hide(root.manifest.id)
  }

  // Test-only seams driven by tests/smoke.sh through `omarchy-shell shell call`.
  function debugResetAll() {
    root.setMode("clock")
    root.hour12 = true
    if (root.service) root.service.debugResetAll()
  }
  function debugAdvancePhase() { if (root.service) root.service.debugAdvancePhase() }
  function debugSetTimerPreset(minutes) {
    return root.service ? root.service.debugSetTimerPreset(minutes) : false
  }
  function debugSetCustomMinutes(minutes) {
    return root.service ? root.service.debugSetCustomMinutes(minutes) : false
  }
  function debugExpireTimer() { if (root.service) root.service.debugExpireTimer() }
  function debugEventsJson() { return root.service ? root.service.debugEventsJson() : "[]" }
  function debugSetEventCapture(enabled) {
    if (root.service)
      root.service.debugEventCapture = (enabled === true || enabled === "true")
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
      screen: root.targetScreen ? root.targetScreen.name : "",
      cueAvailable: root.cueAvailable,
      zenActive: inactivity.zenActive,
      hudOpacity: Math.round(hud.opacity * 100) / 100,
      mode: root.mode,
      serviceReady: root.service !== null,
      pomodoro: root.mode === "pomodoro" && root.service ? {
        phase: root.service.pomodoroEngine.phase,
        remaining: root.service.pomodoroEngine.formattedTime,
        session: root.service.pomodoroEngine.sessionNumber,
        running: root.service.pomodoroEngine.running,
        cycleHalted: root.service.pomodoroEngine.cycleHalted
      } : null,
      timer: root.mode === "timer" && root.service ? {
        remaining: root.service.timerEngine.formattedTime,
        remainingSeconds: root.service.timerEngine.remainingSeconds,
        running: root.service.timerEngine.running,
        duration: root.service.timerEngine.durationMinutes,
        custom: root.service.timerEngine.customActive
      } : null,
      stopwatch: root.mode === "stopwatch" && root.service ? {
        elapsed: root.service.stopwatchEngine.formattedTime,
        elapsedSeconds: root.service.stopwatchEngine.elapsedSeconds,
        elapsedMilliseconds: root.service.stopwatchEngine.elapsedMs,
        running: root.service.stopwatchEngine.running
      } : null
    })
  }

  Component.onCompleted: {
    timezoneProbe.running = true
    cueProbe.running = true
  }

  // Audio cues are the only notification channel; surface tool availability so
  // "no chime" is distinguishable from "no chime player installed".
  Process {
    id: cueProbe
    command: ["bash", "-c", "command -v canberra-gtk-play >/dev/null 2>&1 && echo yes || echo no"]
    stdout: StdioCollector {
      onStreamFinished: root.cueAvailable = (text.trim() === "yes")
    }
  }

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
        root.finishOpen()
      }
    }
    // hyprctl may be unavailable; still show the overlay on the fallback screen.
    // Let a pending onStreamFinished apply the focused screen before mapping.
    onExited: Qt.callLater(root.finishOpen)
  }

  PanelWindow {
    id: panel

    screen: root.targetScreen
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: theme.background

    WlrLayershell.namespace: "zenclock"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
      if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        // Dismiss always wins, even while typing a custom duration.
        inactivity.wake()
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
          return
        }
        // While the custom-minutes field has focus it owns its keystrokes, so
        // typing digits never switches modes or toggles the countdown.
        if (root.mode === "timer" && timerLoader.item
          && timerLoader.item.textEntryActive) return

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
        } else if (root.service && root.mode === "pomodoro" && event.key === Qt.Key_Space) {
          root.service.pomodoroEngine.toggle()
          event.accepted = true
        } else if (root.service && root.mode === "pomodoro" && event.key === Qt.Key_R) {
          root.service.pomodoroEngine.reset()
          event.accepted = true
        } else if (root.service && root.mode === "timer" && event.key === Qt.Key_Space) {
          root.service.timerEngine.toggle()
          event.accepted = true
        } else if (root.service && root.mode === "timer" && event.key === Qt.Key_R) {
          root.service.timerEngine.reset()
          event.accepted = true
        } else if (root.service && root.mode === "stopwatch" && event.key === Qt.Key_Space) {
          root.service.stopwatchEngine.toggle()
          event.accepted = true
        } else if (root.service && root.mode === "stopwatch" && event.key === Qt.Key_R) {
          root.service.stopwatchEngine.reset()
          event.accepted = true
        }
      }

      // Full-window activity sensor. Kept behind the HUD and clock so it
      // never steals their clicks; those forward wake() themselves.
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: inactivity.zenActive ? Qt.BlankCursor : Qt.ArrowCursor
        property real lastX: -1
        property real lastY: -1
        // Ignore synthetic hover events caused by the HUD fading/changing
        // cursor; only real pointer movement should wake Zen Inactivity.
        onPositionChanged: {
          var p = mapToGlobal(mouse.x, mouse.y)
          if (p.x !== lastX || p.y !== lastY) {
            lastX = p.x
            lastY = p.y
            inactivity.wake()
          }
        }
        onPressed: {
          inactivity.wake()
          keyCatcher.forceActiveFocus()
        }
        onReleased: inactivity.wake()
        onClicked: inactivity.wake()
        onWheel: inactivity.wake()
      }

      // Secondary HUD elements. Kept in one group so Zen Inactivity can fade
      // them as a unit without touching the primary time display.
      Item {
        id: hud
        anchors.fill: parent
        opacity: inactivity.zenActive ? 0 : 1
        Behavior on opacity {
          NumberAnimation {
            duration: Style.duration(inactivity.zenActive ? 120 : 180)
            easing.type: Easing.OutCubic
          }
        }

        ZenText {
          anchors { top: parent.top; left: parent.left; topMargin: theme.pageMargin; leftMargin: theme.pageMargin }
          text: strings.t("title")
          role: "label"
          tone: "muted"
        }

        // Mode switcher: label, shortcut number, active rule. No pills, no cards.
        Row {
          anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: theme.space(30) }
          spacing: theme.space(28)

          Repeater {
            model: [
              { mode: "clock", key: "1", label: "pill.clock" },
              { mode: "pomodoro", key: "2", label: "pill.pomodoro" },
              { mode: "timer", key: "3", label: "pill.timer" },
              { mode: "stopwatch", key: "4", label: "pill.stopwatch" }
            ]

            delegate: Item {
              id: tab
              required property var modelData
              property bool current: root.mode === tab.modelData.mode
              property bool hovered: false
              width: tabRow.implicitWidth + theme.space(16)
              height: tabRow.implicitHeight + theme.space(16)

              Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: theme.space(8)

                ZenText {
                  id: tabKey
                  text: tab.modelData.key
                  role: "label"
                  tone: tab.current ? "accent" : (tab.hovered ? "primary" : "muted")
                  anchors.baseline: tabLabel.baseline
                }
                ZenText {
                  id: tabLabel
                  text: strings.t(tab.modelData.label)
                  role: "body"
                  tone: tab.current ? "accent" : (tab.hovered ? "primary" : "secondary")
                  font.weight: tab.current ? Font.DemiBold : Font.Normal
                }
              }

              Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                width: tabRow.implicitWidth
                height: Math.max(2, Math.round(2 * theme.fontScale))
                color: tab.current ? theme.accent : "transparent"
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: inactivity.zenActive ? Qt.BlankCursor : Qt.PointingHandCursor
                onEntered: {
                  tab.hovered = true
                  inactivity.wake()
                }
                onExited: tab.hovered = false
                onClicked: {
                  // First click on a faded HUD only reveals it.
                  if (root.actionLocked) {
                    inactivity.wake()
                    return
                  }
                  root.setMode(tab.modelData.mode)
                }
              }
            }
          }
        }

        Item {
          visible: root.timezoneText !== ""
          anchors { top: parent.top; right: parent.right; topMargin: theme.pageMargin; rightMargin: theme.pageMargin }
          width: zoneLabel.implicitWidth
          height: zoneLabel.implicitHeight

          ZenText {
            id: zoneLabel
            anchors.centerIn: parent
            text: root.timezoneText
            role: "label"
            tone: "secondary"
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: inactivity.zenActive ? Qt.BlankCursor : Qt.ArrowCursor
            onEntered: inactivity.wake()
            onPressed: keyCatcher.forceActiveFocus()
            onClicked: inactivity.wake()
          }
        }

        ZenText {
          anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: theme.pageMargin }
          text: root.hintText
          role: "caption"
          tone: "muted"
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
          spacing: theme.space(16)

          Row {
            id: clockRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: theme.space(10)

            ZenText {
              id: clockLabel
              anchors.verticalCenter: parent.verticalCenter
              text: root.clockText
              role: "hero"
              size: theme.heroSize(panel.width)
            }
            ZenText {
              anchors.baseline: clockLabel.baseline
              text: root.secondsText
              size: clockLabel.font.pixelSize * 0.3
              tone: "secondary"
              font.weight: Font.Light
            }
            ZenText {
              anchors.baseline: clockLabel.baseline
              visible: root.hour12
              text: root.ampmText
              size: clockLabel.font.pixelSize * 0.13
              tone: "accent"
              font.weight: Font.DemiBold
            }
          }

          ZenText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateText
            role: "heading"
            tone: "secondary"
            font.weight: Font.Normal
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: inactivity.zenActive ? Qt.BlankCursor : Qt.PointingHandCursor
          onPressed: keyCatcher.forceActiveFocus()
          onClicked: {
            if (root.actionLocked) {
              inactivity.wake()
              return
            }
            root.toggleFormat()
          }
        }
      }

      Loader {
        active: root.service !== null
        anchors.fill: parent
        sourceComponent: Component {
          PomodoroView {
            visible: root.mode === "pomodoro"
            anchors.fill: parent
            engine: root.service.pomodoroEngine
            hudFaded: inactivity.zenActive
            actionLocked: root.actionLocked
            onActivity: inactivity.wake()
          }
        }
      }

      Loader {
        id: timerLoader
        active: root.service !== null
        anchors.fill: parent
        sourceComponent: Component {
          TimerView {
            visible: root.mode === "timer"
            anchors.fill: parent
            engine: root.service.timerEngine
            hudFaded: inactivity.zenActive
            actionLocked: root.actionLocked
            onActivity: inactivity.wake()
            onFocusRestored: keyCatcher.forceActiveFocus()
          }
        }
      }

      Loader {
        active: root.service !== null
        anchors.fill: parent
        sourceComponent: Component {
          StopwatchView {
            visible: root.mode === "stopwatch"
            anchors.fill: parent
            engine: root.service.stopwatchEngine
            hudFaded: inactivity.zenActive
            actionLocked: root.actionLocked
            onActivity: inactivity.wake()
          }
        }
      }
    }
  }
}

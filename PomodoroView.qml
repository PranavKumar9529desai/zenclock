pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Fullscreen Pomodoro view. Purely presentational: all state and transitions
// live in PomodoroEngine, injected through `engine` by Overlay.qml.
Item {
  id: root

  required property var engine
  property bool hudFaded: false

  // Raised on any pointer interaction so the owner can wake Zen Inactivity.
  signal activity()

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property string phaseLabel: {
    if (root.engine.phase === "shortBreak") return strings.t("pomodoro.phase.shortBreak")
    if (root.engine.phase === "longBreak") return strings.t("pomodoro.phase.longBreak")
    if (root.engine.phase === "cycleComplete") return strings.t("pomodoro.phase.cycleComplete")
    return strings.t("pomodoro.phase.focus")
  }

  readonly property color phaseColor: {
    if (root.engine.phase === "focus" || root.engine.cycleHalted) return "#7dd3fc"
    return "#9ab9c9"
  }

  readonly property string actionLabel: {
    if (root.engine.cycleHalted) return strings.t("pomodoro.action.newCycle")
    if (root.engine.running) return strings.t("pomodoro.action.pause")
    return root.engine.remainingSeconds < root.engine.focusMinutes * 60
      ? strings.t("pomodoro.action.resume")
      : strings.t("pomodoro.action.play")
  }

  readonly property string playGlyph: root.engine.running ? "󰏤" : "󰐊"

  Column {
    id: content
    anchors.centerIn: parent
    spacing: 18

    Row {
      id: phaseRow
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }

      PlainText {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰔛"
        font.pixelSize: 24
        font.family: Style.font.family
        color: root.phaseColor
      }
      PlainText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.phaseLabel
        font.pixelSize: 18
        font.letterSpacing: 4
        font.family: Style.font.family
        color: root.phaseColor
      }
    }

    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.engine.formattedTime
      font.pixelSize: Math.min(root.width * 0.16, 280)
      font.weight: Font.Light
      font.family: Style.font.family
      color: "#f4f4f8"
    }

    PlainText {
      id: sessionLabel
      anchors.horizontalCenter: parent.horizontalCenter
      text: strings.t("pomodoro.session")
        .arg(Commons.I18n.formatNumber(root.engine.sessionNumber))
        .arg(Commons.I18n.formatNumber(root.engine.sessionsPerCycle))
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }
      font.pixelSize: 20
      font.family: Style.font.family
      color: "#9a9aa6"
    }

    // Pomodoro Cycle progress: one native pomodoro glyph per Focus Session.
    Row {
      id: progressRow
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 16
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }

      Repeater {
        model: root.engine.sessionsPerCycle

        delegate: PlainText {
          required property int index
          text: "󰔛"
          font.pixelSize: 26
          font.family: Style.font.family
          color: {
            if (root.engine.completedFocusSessions > index) return "#7dd3fc"
            if (!root.engine.cycleHalted && root.engine.sessionNumber - 1 === index) return "#f4f4f8"
            return "#3a3a44"
          }
        }
      }
    }

    PlainText {
      id: promptLabel
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.engine.cycleHalted
      text: strings.t("pomodoro.cyclePrompt")
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }
      font.pixelSize: 15
      font.family: Style.font.family
      color: "#7dd3fc"
    }

    Row {
      id: controlsRow
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 16
      topPadding: 8
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }

      HudButton {
        accent: true
        faded: root.hudFaded
        label: strings.t("pomodoro.controls.primary").arg(root.playGlyph).arg(root.actionLabel)
        onActivity: root.activity()
        onClicked: root.engine.toggle()
      }

      HudButton {
        faded: root.hudFaded
        label: strings.t("pomodoro.controls.primary").arg("󰑐").arg(strings.t("pomodoro.action.reset"))
        onActivity: root.activity()
        onClicked: root.engine.reset()
      }

      HudButton {
        faded: root.hudFaded
        interactive: root.engine.canSkip
        label: strings.t("pomodoro.controls.primary").arg("󰒭").arg(strings.t("pomodoro.action.skip"))
        onActivity: root.activity()
        onClicked: root.engine.skip()
      }
    }

    PlainText {
      id: hintLabel
      anchors.horizontalCenter: parent.horizontalCenter
      text: strings.t("pomodoro.hint")
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }
      font.pixelSize: 13
      font.letterSpacing: 2
      font.family: Style.font.family
      color: "#55555f"
    }
  }
}

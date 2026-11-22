pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Fullscreen Pomodoro view. Purely presentational: all state and transitions
// live in PomodoroEngine, injected through `engine` by Overlay.qml.
Item {
  id: root

  property var engine: null

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property string phaseLabel: {
    if (!root.engine) return strings.t("pomodoro.phase.focus")
    if (root.engine.phase === "shortBreak") return strings.t("pomodoro.phase.shortBreak")
    if (root.engine.phase === "longBreak") return strings.t("pomodoro.phase.longBreak")
    if (root.engine.phase === "cycleComplete") return strings.t("pomodoro.phase.cycleComplete")
    return strings.t("pomodoro.phase.focus")
  }

  readonly property color phaseColor: {
    if (!root.engine) return "#7dd3fc"
    if (root.engine.phase === "focus" || root.engine.cycleHalted) return "#7dd3fc"
    return "#9ab9c9"
  }

  readonly property string actionLabel: {
    if (!root.engine || root.engine.cycleHalted) return strings.t("pomodoro.action.newCycle")
    if (root.engine.running) return strings.t("pomodoro.action.pause")
    return root.engine.remainingSeconds < root.engine.focusMinutes * 60
      ? strings.t("pomodoro.action.resume")
      : strings.t("pomodoro.action.play")
  }

  readonly property string playGlyph: root.engine && root.engine.running ? "󰏤" : "󰐊"

  Column {
    id: content
    anchors.centerIn: parent
    spacing: 18

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14

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
      text: root.engine ? root.engine.formattedTime : "25:00"
      font.pixelSize: Math.min(root.width * 0.16, 280)
      font.weight: Font.Light
      font.family: Style.font.family
      color: "#f4f4f8"
    }

    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: strings.t("pomodoro.session")
        .arg(Commons.I18n.formatNumber(root.engine ? root.engine.sessionNumber : 1))
        .arg(Commons.I18n.formatNumber(root.engine ? root.engine.sessionsPerCycle : 4))
      font.pixelSize: 20
      font.family: Style.font.family
      color: "#9a9aa6"
    }

    // Pomodoro Cycle progress: one native pomodoro glyph per Focus Session.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 16

      Repeater {
        model: 4

        delegate: PlainText {
          required property int index
          text: "󰔛"
          font.pixelSize: 26
          font.family: Style.font.family
          color: {
            if (!root.engine) return index === 0 ? "#f4f4f8" : "#3a3a44"
            if (root.engine.completedFocusSessions > index) return "#7dd3fc"
            if (!root.engine.cycleHalted && root.engine.sessionNumber - 1 === index) return "#f4f4f8"
            return "#3a3a44"
          }
        }
      }
    }

    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.engine !== null && root.engine.cycleHalted
      text: strings.t("pomodoro.cyclePrompt")
      font.pixelSize: 15
      font.family: Style.font.family
      color: "#7dd3fc"
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 16
      topPadding: 8

      // Play / Pause / Start New Cycle (Space).
      Rectangle {
        id: primaryButton
        radius: 12
        color: primaryArea.containsMouse ? "#1e2a33" : "#141419"
        border.color: "#7dd3fc"
        border.width: 1
        implicitWidth: primaryLabel.implicitWidth + 48
        implicitHeight: primaryLabel.implicitHeight + 22

        Behavior on color {
          ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
        }

        PlainText {
          id: primaryLabel
          anchors.centerIn: parent
          text: strings.t("pomodoro.controls.primary").arg(root.playGlyph).arg(root.actionLabel)
          font.pixelSize: 15
          font.family: Style.font.family
          color: "#7dd3fc"
        }

        MouseArea {
          id: primaryArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.engine) root.engine.toggle()
        }
      }

      // Reset (R).
      Rectangle {
        id: resetButton
        radius: 12
        color: resetArea.containsMouse ? "#1e1e26" : "#141419"
        border.color: "#2a2a34"
        border.width: 1
        implicitWidth: resetLabel.implicitWidth + 40
        implicitHeight: resetLabel.implicitHeight + 22

        Behavior on color {
          ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
        }

        PlainText {
          id: resetLabel
          anchors.centerIn: parent
          text: strings.t("pomodoro.controls.glyphLabel").arg("󰑐").arg(strings.t("pomodoro.action.reset"))
          font.pixelSize: 15
          font.family: Style.font.family
          color: "#b6b6c2"
        }

        MouseArea {
          id: resetArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.engine) root.engine.reset()
        }
      }

      // Skip break (break phases only).
      Rectangle {
        id: skipButton
        opacity: root.engine && root.engine.canSkip ? 1 : 0.35
        radius: 12
        color: skipArea.containsMouse ? "#1e1e26" : "#141419"
        border.color: "#2a2a34"
        border.width: 1
        implicitWidth: skipLabel.implicitWidth + 40
        implicitHeight: skipLabel.implicitHeight + 22

        Behavior on color {
          ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
        }

        PlainText {
          id: skipLabel
          anchors.centerIn: parent
          text: strings.t("pomodoro.controls.glyphLabel").arg("󰒭").arg(strings.t("pomodoro.action.skip"))
          font.pixelSize: 15
          font.family: Style.font.family
          color: "#b6b6c2"
        }

        MouseArea {
          id: skipArea
          anchors.fill: parent
          hoverEnabled: root.engine && root.engine.canSkip
          enabled: root.engine && root.engine.canSkip
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.engine && root.engine.canSkip) root.engine.skip()
        }
      }
    }

    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: strings.t("pomodoro.hint")
      font.pixelSize: 13
      font.letterSpacing: 2
      font.family: Style.font.family
      color: "#55555f"
    }
  }
}

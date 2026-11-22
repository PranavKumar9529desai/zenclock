pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Fullscreen Stopwatch view. Purely presentational: all state lives in
// StopwatchEngine, injected as `engine` by Overlay.qml.
Item {
  id: root

  property var engine: null
  // Set by the overlay owner when Zen Inactivity fades secondary HUD elements.
  // The primary MM:SS / HH:MM:SS digits stay visible.
  property bool hudFaded: false

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property string playGlyph: root.engine && root.engine.running ? "󰏤" : "󰐊"
  readonly property string actionLabel: {
    if (!root.engine) return strings.t("stopwatch.action.play")
    if (root.engine.running) return strings.t("stopwatch.action.pause")
    return root.engine.elapsedSeconds > 0
      ? strings.t("stopwatch.action.resume")
      : strings.t("stopwatch.action.play")
  }

  Column {
    anchors.centerIn: parent
    spacing: 18

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

      PlainText {
        anchors.verticalCenter: parent.verticalCenter
        text: "⏱"
        font.pixelSize: 24
        font.family: Style.font.family
        color: "#7dd3fc"
      }
      PlainText {
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t("stopwatch.label")
        font.pixelSize: 18
        font.letterSpacing: 4
        font.family: Style.font.family
        color: "#7dd3fc"
      }
    }

    // Primary digits — never faded. The engine switches to HH:MM:SS past an hour.
    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.engine ? root.engine.formattedTime : "00:00"
      font.pixelSize: Math.min(root.width * 0.16, 280)
      font.weight: Font.Light
      font.family: Style.font.family
      color: "#f4f4f8"
    }

    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.engine && root.engine.running
        ? strings.t("stopwatch.status.running")
        : strings.t("stopwatch.status.idle")
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
      font.pixelSize: 18
      font.family: Style.font.family
      color: root.engine && root.engine.running ? "#7dd3fc" : "#9a9aa6"
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 16
      topPadding: 8
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

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
          text: strings.t("stopwatch.controls.primary").arg(root.playGlyph).arg(root.actionLabel)
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
          text: strings.t("stopwatch.controls.glyphLabel").arg("󰑐").arg(strings.t("stopwatch.action.reset"))
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
    }

    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: strings.t("stopwatch.hint")
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
      font.pixelSize: 13
      font.letterSpacing: 2
      font.family: Style.font.family
      color: "#55555f"
    }
  }
}

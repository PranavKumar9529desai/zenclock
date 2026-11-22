pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Fullscreen Stopwatch view. Purely presentational: all state lives in
// StopwatchEngine, injected as `engine` by Overlay.qml.
Item {
  id: root

  required property var engine
  property bool hudFaded: false
  property bool actionLocked: false

  // Raised on any pointer interaction so the owner can wake Zen Inactivity.
  signal activity()

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property string playGlyph: root.engine.running ? "󰏤" : "󰐊"
  readonly property string actionLabel: {
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
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }

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
      text: root.engine.formattedTime
      font.pixelSize: Math.min(root.width * 0.16, 280)
      font.weight: Font.Light
      font.family: Style.font.family
      color: "#f4f4f8"
    }

    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.engine.running
        ? strings.t("stopwatch.status.running")
        : strings.t("stopwatch.status.idle")
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }
      font.pixelSize: 18
      font.family: Style.font.family
      color: root.engine.running ? "#7dd3fc" : "#9a9aa6"
    }

    Row {
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
        locked: root.actionLocked
        label: strings.t("stopwatch.controls.primary").arg(root.playGlyph).arg(root.actionLabel)
        onActivity: root.activity()
        onClicked: root.engine.toggle()
      }

      HudButton {
        faded: root.hudFaded
        locked: root.actionLocked
        label: strings.t("stopwatch.controls.primary").arg("󰑐").arg(strings.t("stopwatch.action.reset"))
        onActivity: root.activity()
        onClicked: root.engine.reset()
      }
    }

    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: strings.t("stopwatch.hint")
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

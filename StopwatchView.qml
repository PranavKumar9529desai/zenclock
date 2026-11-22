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

  signal activity()

  ZenTheme { id: theme }
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
    spacing: theme.space(20)

    ZenText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: strings.t("stopwatch.label")
      role: "heading"
      tone: root.engine.running ? "accent" : "secondary"
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic }
      }
    }

    // Primary digits are never faded. The engine switches to HH:MM:SS past an hour.
    ZenText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.engine.formattedTime
      role: "hero"
      size: theme.heroSize(root.width)
    }

    ZenText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.engine.running
        ? strings.t("stopwatch.status.running")
        : strings.t("stopwatch.status.idle")
      role: "body"
      tone: root.engine.running ? "accent" : "secondary"
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic }
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: theme.space(12)
      topPadding: theme.space(10)
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic }
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
  }
}

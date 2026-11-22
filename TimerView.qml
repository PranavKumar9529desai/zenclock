pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Fullscreen Countdown Timer view. Purely presentational: all state and
// transitions live in TimerEngine, injected as `engine` by Overlay.qml.
Item {
  id: root

  required property var engine
  property bool hudFaded: false

  // Raised on any pointer interaction so the owner can wake Zen Inactivity.
  signal activity()
  // Raised when the custom-minutes field or a control is used, so the owner
  // can return focus to its global key catcher and keep Space / R / 1-4 live.
  signal focusRestored()

  readonly property bool textEntryActive: customInput.activeFocus

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property string playGlyph: root.engine.running ? "󰏤" : "󰐊"
  readonly property string actionLabel: {
    if (root.engine.running) return strings.t("timer.action.pause")
    return root.engine.remainingSeconds > 0 && root.engine.remainingSeconds < root.engine.durationSeconds
      ? strings.t("timer.action.resume")
      : strings.t("timer.action.play")
  }
  readonly property string durationLabel: {
    var minutes = Commons.I18n.formatNumber(root.engine.durationMinutes)
    return root.engine.customActive
      ? strings.t("timer.custom.active").arg(minutes)
      : strings.t("timer.preset.active").arg(minutes)
  }

  Column {
    anchors.centerIn: parent
    spacing: 18

    // Secondary heading (fades with Zen Inactivity).
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }

      PlainText {
        anchors.verticalCenter: parent.verticalCenter
        text: "⧖"
        font.pixelSize: 24
        font.family: Style.font.family
        color: "#7dd3fc"
      }
      PlainText {
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t("timer.label")
        font.pixelSize: 18
        font.letterSpacing: 4
        font.family: Style.font.family
        color: "#7dd3fc"
      }
    }

    // Primary countdown digits — never faded.
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
      text: root.durationLabel
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }
      font.pixelSize: 18
      font.family: Style.font.family
      color: "#9a9aa6"
    }

    // Quick presets: 5m / 15m / 25m / 45m / 60m.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 10
      topPadding: 6
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }

      Repeater {
        model: root.engine.presets

        delegate: Rectangle {
          id: preset
          required property int modelData
          property bool hovered: false
          property bool selected: !root.engine.customActive
            && root.engine.durationMinutes === preset.modelData

          radius: 10
          color: selected ? "#1b2a33" : (hovered ? "#1e1e26" : "#141419")
          border.color: selected ? "#7dd3fc" : "#2a2a34"
          border.width: 1
          implicitWidth: presetLabel.implicitWidth + 30
          implicitHeight: presetLabel.implicitHeight + 16

          Behavior on color {
            ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
          }

          PlainText {
            id: presetLabel
            anchors.centerIn: parent
            text: strings.t("timer.preset").arg(Commons.I18n.formatNumber(preset.modelData))
            font.pixelSize: 14
            font.letterSpacing: 1
            font.family: Style.font.family
            color: parent.selected ? "#7dd3fc" : "#b6b6c2"
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.hudFaded ? Qt.BlankCursor : Qt.PointingHandCursor
            onEntered: preset.hovered = true
            onExited: preset.hovered = false
            onPositionChanged: root.activity()
            onClicked: {
              root.activity()
              root.engine.setPreset(preset.modelData)
              // A typed-but-unconfirmed value must not outlive a preset click.
              customInput.text = String(root.engine.customMinutes)
              root.focusRestored()
            }
          }
        }
      }
    }

    // Custom minutes entry, validated by the engine to the 1-180 range.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 12
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(root.hudFaded ? 120 : 180); easing.type: Easing.OutCubic }
      }

      PlainText {
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t("timer.custom.label")
        font.pixelSize: 13
        font.letterSpacing: 2
        font.family: Style.font.family
        color: "#8a8a96"
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 72
        height: 34
        radius: 8
        color: "#141419"
        border.color: customInput.activeFocus ? "#7dd3fc" : "#2a2a34"
        border.width: 1

        // TextInput is plain text by nature (no rich-text rendering), so it
        // satisfies the same safety rule as the PlainText display elements.
        TextInput {
          id: customInput
          anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
          text: String(root.engine.customMinutes)
          color: "#f4f4f8"
          font.pixelSize: 15
          font.family: Style.font.family
          inputMethodHints: Qt.ImhDigitsOnly
          validator: IntValidator { bottom: root.engine.minMinutes; top: root.engine.maxMinutes }
          maximumLength: 3
          selectByMouse: true

          Keys.onEscapePressed: {
            customInput.text = String(root.engine.customMinutes)
            root.focusRestored()
            event.accepted = true
          }
          onAccepted: {
            var value = parseInt(customInput.text, 10)
            if (!root.engine.setCustomMinutes(value))
              customInput.text = String(root.engine.customMinutes)
            root.focusRestored()
          }
        }
      }

      PlainText {
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t("timer.custom.unit")
        font.pixelSize: 13
        font.family: Style.font.family
        color: "#8a8a96"
      }

      PlainText {
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t("timer.custom.hint")
        font.pixelSize: 12
        font.letterSpacing: 1
        font.family: Style.font.family
        color: "#55555f"
      }
    }

    // Play / Pause (Space) and Reset (R).
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
        label: strings.t("timer.controls.primary").arg(root.playGlyph).arg(root.actionLabel)
        onActivity: root.activity()
        onClicked: {
          root.engine.toggle()
          root.focusRestored()
        }
      }

      HudButton {
        faded: root.hudFaded
        label: strings.t("timer.controls.primary").arg("󰑐").arg(strings.t("timer.action.reset"))
        onActivity: root.activity()
        onClicked: {
          root.engine.reset()
          root.focusRestored()
        }
      }
    }

    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: strings.t("timer.hint")
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

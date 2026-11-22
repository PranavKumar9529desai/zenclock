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
  property bool actionLocked: false

  signal activity()
  signal focusRestored()

  readonly property bool textEntryActive: customInput.activeFocus

  ZenTheme { id: theme }
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
    spacing: theme.space(20)

    ZenText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: strings.t("timer.label")
      role: "heading"
      tone: "accent"
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic }
      }
    }

    ZenText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.engine.formattedTime
      role: "hero"
      size: theme.heroSize(root.width)
    }

    ZenText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.durationLabel
      role: "body"
      tone: "secondary"
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic }
      }
    }

    // Presets are labels with an active rule, not a row of identical cards.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: theme.space(24)
      topPadding: theme.space(8)
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic }
      }

      Repeater {
        model: root.engine.presets

        delegate: Item {
          id: preset
          required property int modelData
          property bool hovered: false
          property bool selected: !root.engine.customActive
            && root.engine.durationMinutes === preset.modelData

          width: presetLabel.implicitWidth + theme.space(20)
          height: presetLabel.implicitHeight + theme.space(16)

          ZenText {
            id: presetLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            text: strings.t("timer.preset").arg(Commons.I18n.formatNumber(preset.modelData))
            role: "label"
            tone: preset.selected ? "accent" : (preset.hovered ? "primary" : "secondary")
          }

          Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            width: presetLabel.implicitWidth
            height: Math.max(2, Math.round(2 * theme.fontScale))
            color: preset.selected ? theme.accent : "transparent"
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.hudFaded ? Qt.BlankCursor : Qt.PointingHandCursor
            onEntered: preset.hovered = true
            onExited: preset.hovered = false
            onPositionChanged: root.activity()
            onClicked: {
              if (root.actionLocked) {
                root.activity()
                return
              }
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
      spacing: theme.space(10)
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic }
      }

      ZenText {
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t("timer.custom.label")
        role: "label"
        tone: "muted"
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: theme.space(76)
        height: theme.space(38)
        radius: theme.radius
        color: theme.surface
        border.color: customInput.activeFocus ? theme.accent : theme.line
        border.width: 1

        // TextInput is plain text by nature (no rich-text rendering), so it
        // satisfies the same safety rule as the ZenText display elements.
        TextInput {
          id: customInput
          anchors { fill: parent; leftMargin: theme.space(6); rightMargin: theme.space(6) }
          text: String(root.engine.customMinutes)
          color: theme.textPrimary
          font.pixelSize: theme.body
          font.family: Style.font.family
          horizontalAlignment: TextInput.AlignHCenter
          verticalAlignment: TextInput.AlignVCenter
          inputMethodHints: Qt.ImhDigitsOnly
          validator: IntValidator { bottom: root.engine.minMinutes; top: root.engine.maxMinutes }
          maximumLength: 3
          selectByMouse: true
          readOnly: root.actionLocked

          onAccepted: {
            var value = parseInt(customInput.text, 10)
            if (!root.engine.setCustomMinutes(value))
              customInput.text = String(root.engine.customMinutes)
            root.focusRestored()
          }
        }
      }

      ZenText {
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t("timer.custom.unit")
        role: "label"
        tone: "muted"
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
        label: strings.t("timer.controls.primary").arg(root.playGlyph).arg(root.actionLabel)
        onActivity: root.activity()
        onClicked: {
          root.engine.toggle()
          root.focusRestored()
        }
      }
      HudButton {
        faded: root.hudFaded
        locked: root.actionLocked
        label: strings.t("timer.controls.primary").arg("󰑐").arg(strings.t("timer.action.reset"))
        onActivity: root.activity()
        onClicked: {
          root.engine.reset()
          root.focusRestored()
        }
      }
    }
  }
}

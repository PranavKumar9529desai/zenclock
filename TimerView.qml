pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Fullscreen Countdown Timer view. Purely presentational: all state and
// transitions live in TimerEngine, injected as `engine` by Overlay.qml.
Item {
  id: root

  property var engine: null
  // Set by the overlay owner when Zen Inactivity fades secondary HUD elements.
  // The primary MM:SS digits stay visible.
  property bool hudFaded: false

  // Raised when the custom-minutes field (or a control) is used, so the owner
  // can return focus to its global key catcher and keep Space / R / 1-4 live.
  signal focusRestored()

  readonly property bool textEntryActive: customInput.activeFocus

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property string playGlyph: root.engine && root.engine.running ? "󰏤" : "󰐊"
  readonly property string actionLabel: {
    if (!root.engine) return strings.t("timer.action.play")
    if (root.engine.running) return strings.t("timer.action.pause")
    return root.engine.remainingSeconds < root.engine.durationSeconds
      ? strings.t("timer.action.resume")
      : strings.t("timer.action.play")
  }
  readonly property string durationLabel: {
    if (!root.engine) return strings.t("timer.preset.active").arg(Commons.I18n.formatNumber(5))
    var minutes = Commons.I18n.formatNumber(root.engine.durationMinutes)
    return root.engine.customActive
      ? strings.t("timer.custom.active").arg(minutes)
      : strings.t("timer.preset.active").arg(minutes)
  }

  function restoreFocus() { root.focusRestored() }

  Column {
    anchors.centerIn: parent
    spacing: 18

    // Secondary heading (fades with Zen Inactivity).
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

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
      text: root.engine ? root.engine.formattedTime : "05:00"
      font.pixelSize: Math.min(root.width * 0.16, 280)
      font.weight: Font.Light
      font.family: Style.font.family
      color: "#f4f4f8"
    }

    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.durationLabel
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
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
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

      Repeater {
        model: root.engine ? root.engine.presets : [5, 15, 25, 45, 60]

        delegate: Rectangle {
          id: preset
          required property int modelData

          property bool hovered: false
          property bool selected: root.engine !== null
            && !root.engine.customActive
            && root.engine.durationMinutes === modelData

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
            cursorShape: Qt.PointingHandCursor
            onEntered: parent.hovered = true
            onExited: parent.hovered = false
            onClicked: {
              if (root.engine) root.engine.setPreset(preset.modelData)
              root.restoreFocus()
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
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

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
          text: root.engine ? String(root.engine.customMinutes) : "10"
          color: "#f4f4f8"
          font.pixelSize: 15
          font.family: Style.font.family
          inputMethodHints: Qt.ImhDigitsOnly
          validator: IntValidator { bottom: root.engine ? root.engine.minMinutes : 1; top: root.engine ? root.engine.maxMinutes : 180 }
          maximumLength: 3
          selectByMouse: true
          onAccepted: {
            var value = parseInt(customInput.text, 10)
            if (!root.engine || !root.engine.setCustomMinutes(value))
              customInput.text = root.engine ? String(root.engine.customMinutes) : "10"
            root.restoreFocus()
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
          text: strings.t("timer.controls.primary").arg(root.playGlyph).arg(root.actionLabel)
          font.pixelSize: 15
          font.family: Style.font.family
          color: "#7dd3fc"
        }

        MouseArea {
          id: primaryArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.engine) root.engine.toggle()
            root.restoreFocus()
          }
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
          text: strings.t("timer.controls.glyphLabel").arg("󰑐").arg(strings.t("timer.action.reset"))
          font.pixelSize: 15
          font.family: Style.font.family
          color: "#b6b6c2"
        }

        MouseArea {
          id: resetArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.engine) root.engine.reset()
            root.restoreFocus()
          }
        }
      }
    }

    PlainText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: strings.t("timer.hint")
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
      font.pixelSize: 13
      font.letterSpacing: 2
      font.family: Style.font.family
      color: "#55555f"
    }
  }
}

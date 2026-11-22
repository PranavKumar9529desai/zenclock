pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// Shared HUD control. `accent` marks the primary action; `interactive` dims a
// conditional action such as "Skip break". `activity` is separate from
// `clicked` so the owner can wake Zen Inactivity without firing the action.
Rectangle {
  id: root

  property string label: ""
  property bool accent: false
  property bool faded: false
  property bool locked: false
  property bool interactive: true

  signal clicked()
  signal activity()

  ZenTheme { id: theme }

  radius: theme.radius
  color: area.containsMouse ? theme.surfaceHover : theme.surface
  border.color: root.accent ? theme.accent : theme.line
  border.width: 1

  implicitWidth: buttonLabel.implicitWidth + theme.space(44)
  implicitHeight: buttonLabel.implicitHeight + theme.space(20)
  opacity: root.interactive ? 1 : 0.4

  Behavior on opacity {
    NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic }
  }
  Behavior on color {
    ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
  }

  ZenText {
    id: buttonLabel
    anchors.centerIn: parent
    text: root.label
    role: "label"
    tone: root.accent ? "accent" : "secondary"
    font.weight: root.accent ? Font.DemiBold : Font.Normal
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: root.interactive
    enabled: root.interactive
    cursorShape: root.faded ? Qt.BlankCursor : Qt.PointingHandCursor
    onEntered: root.activity()
    onClicked: {
      // A click on a just-revealed control only wakes the HUD.
      if (root.locked) {
        root.activity()
        return
      }
      root.clicked()
    }
  }
}

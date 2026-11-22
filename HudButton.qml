pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// Shared HUD control. `accent` marks the primary action; `interactive` dims and
// disables conditional actions such as "Skip break". Both `clicked` and
// `activity` are explicit so the owner can wake Zen Inactivity independently
// of the action itself.
Rectangle {
  id: root

  property string label: ""
  property bool accent: false
  property bool faded: false
  property bool interactive: true

  signal clicked()
  signal activity()

  radius: 12
  color: area.containsMouse ? (root.accent ? "#1e2a33" : "#1e1e26") : "#141419"
  border.color: root.accent ? "#7dd3fc" : "#2a2a34"
  border.width: 1
  implicitWidth: buttonLabel.implicitWidth + (root.accent ? 48 : 40)
  implicitHeight: buttonLabel.implicitHeight + 22
  opacity: root.interactive ? 1 : 0.35

  Behavior on opacity {
    NumberAnimation { duration: Style.duration(root.faded ? 120 : 180); easing.type: Easing.OutCubic }
  }
  Behavior on color {
    ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
  }

  PlainText {
    id: buttonLabel
    anchors.centerIn: parent
    text: root.label
    font.pixelSize: 15
    font.family: Style.font.family
    color: root.accent ? "#7dd3fc" : "#b6b6c2"
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: root.interactive
    enabled: root.interactive
    cursorShape: root.faded ? Qt.BlankCursor : Qt.PointingHandCursor
    onEntered: root.activity()
    onClicked: {
      // A click on an invisible control reveals the HUD without acting.
      if (root.faded) {
        root.activity()
        return
      }
      root.clicked()
    }
  }
}

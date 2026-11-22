pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

/**
 * Zen Inactivity controller.
 *
 * Self-contained and reusable: the owner supplies the secondary HUD group to
 * fade, sets `active` with the overlay's visibility, and calls `wake()`
 * from every user-input handler. Everything else (idle counting, state, fade
 * timing, easing) lives here.
 */
Item {
  id: root

  // Only count idle time while the overlay is actually visible. Named
  // `active` because `enabled` is already a QQuickItem property.
  property bool active: false
  property int idleTimeout: 3000

  // Secondary HUD group whose opacity is animated as a unit.
  property Item target: null

  readonly property bool zenActive: root.active && root.zen

  property bool zen: false

  /** Reset the idle countdown and immediately bring the HUD back. */
  function wake() {
    root.zen = false
    if (root.active) idleTimer.restart()
  }

  onActiveChanged: {
    root.zen = false
    if (root.active) idleTimer.restart()
    else idleTimer.stop()
  }

  Component.onCompleted: {
    if (root.active) idleTimer.restart()
  }

  Timer {
    id: idleTimer
    interval: root.idleTimeout
    repeat: false
    running: false
    onTriggered: root.zen = true
  }

  // Per Plugin Motion: exits are shorter than entrances. Fading the HUD out
  // is the exit (120ms); fading it back in on wake is the entrance (180ms).
  PropertyAnimation {
    id: hudFade
    target: root.target
    property: "opacity"
    to: root.zenActive ? 0 : 1
    duration: root.zenActive ? Style.duration(120) : Style.duration(180)
    easing.type: Easing.OutCubic
  }

  onZenActiveChanged: hudFade.restart()
}

pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

/**
 * Zen Inactivity controller.
 *
 * The HUD is pinned visible whenever the overlay opens. Only after a grace
 * period, and then after `idleTimeout` with no input, does the secondary HUD
 * fade. Any input restores it and restarts the countdown.
 */
Item {
  id: root

  // Named `active` because `enabled` is already a QQuickItem property.
  property bool active: false
  // Controls stay visible for this long after opening before idle counting.
  property int graceTimeout: 8000
  property int idleTimeout: 3000

  // Secondary HUD group whose opacity is animated as a unit.
  property Item target: null

  readonly property bool zenActive: root.active && !root.inGrace && root.zen

  property bool inGrace: false
  property bool zen: false

  /** Reset the idle countdown and immediately bring the HUD back. */
  function wake() {
    root.zen = false
    if (!root.active) return
    if (root.inGrace) graceTimer.restart()
    else idleTimer.restart()
  }

  onActiveChanged: {
    root.zen = false
    idleTimer.stop()
    graceTimer.stop()
    // Opening always shows the controls via the owner's opacity binding.
    root.inGrace = root.active
    if (root.active) graceTimer.restart()
  }

  Timer {
    id: graceTimer
    interval: root.graceTimeout
    repeat: false
    onTriggered: {
      root.inGrace = false
      idleTimer.restart()
    }
  }

  Timer {
    id: idleTimer
    interval: root.idleTimeout
    repeat: false
    onTriggered: root.zen = true
  }

  // The HUD owner binds its opacity to `zenActive` with a Behavior. Keeping
  // the animation at the owner avoids a one-shot animation fighting the
  // explicit "visible on open" reset in onActiveChanged.
}

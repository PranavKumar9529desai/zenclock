pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "timer-policy.js" as TimerPolicy

// Fullscreen Pomodoro view. Purely presentational: all state and transitions
// live in PomodoroEngine, injected through `engine` by Overlay.qml.
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

  readonly property string phaseLabel: {
    if (root.engine.phase === "shortBreak") return strings.t("pomodoro.phase.shortBreak")
    if (root.engine.phase === "longBreak") return strings.t("pomodoro.phase.longBreak")
    if (root.engine.phase === "cycleComplete") return strings.t("pomodoro.phase.cycleComplete")
    return strings.t("pomodoro.phase.focus")
  }
  readonly property bool phaseActive: root.engine.phase === "focus" || root.engine.cycleHalted

  // A restored or paused Short/Long Break is partially elapsed too, so its
  // primary button reads "Resume" just like a Focus Session. Label only:
  // no new UI and no change to the engine's transitions.
  readonly property bool phasePartiallyElapsed: TimerPolicy.isPartiallyElapsed(
    root.engine.phase, root.engine.remainingSeconds,
    root.engine.focusMinutes, root.engine.shortBreakMinutes,
    root.engine.longBreakMinutes)

  readonly property string actionLabel: {
    if (root.engine.cycleHalted) return strings.t("pomodoro.action.newCycle")
    if (root.engine.running) return strings.t("pomodoro.action.pause")
    // The shared pure policy already derives "Resume" from the active phase's
    // own duration (the V1 fix) and extends it to every active phase, including
    // a restored Short/Long Break; keep one derivation to avoid drift.
    return root.phasePartiallyElapsed
      ? strings.t("pomodoro.action.resume")
      : strings.t("pomodoro.action.play")
  }
  readonly property string playGlyph: root.engine.running ? "󰏤" : "󰐊"

  Column {
    anchors.centerIn: parent
    spacing: theme.space(20)

    ZenText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.phaseLabel
      role: "heading"
      tone: root.phaseActive ? "accent" : "secondary"
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
      text: strings.t("pomodoro.session")
        .arg(Commons.I18n.formatNumber(root.engine.sessionNumber))
        .arg(Commons.I18n.formatNumber(root.engine.sessionsPerCycle))
      role: "body"
      tone: "secondary"
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic }
      }
    }

    // One bar per Focus Session: filled = done, bright = current, outlined = to do.
    Row {
      id: progressRow
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: theme.space(8)
      opacity: root.hudFaded ? 0 : 1
      Behavior on opacity {
        NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic }
      }

      Repeater {
        model: root.engine.sessionsPerCycle

        delegate: Rectangle {
          required property int index
          width: theme.space(30)
          height: Math.max(2, Math.round(2 * theme.fontScale))
          color: {
            if (root.engine.completedFocusSessions > index) return theme.accent
            if (!root.engine.cycleHalted && root.engine.sessionNumber - 1 === index)
              return theme.textPrimary
            return theme.line
          }
        }
      }
    }

    ZenText {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.engine.cycleHalted
      text: strings.t("pomodoro.cyclePrompt")
      role: "label"
      tone: "accent"
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
        label: strings.t("pomodoro.controls.primary").arg(root.playGlyph).arg(root.actionLabel)
        onActivity: root.activity()
        onClicked: root.engine.toggle()
      }
      HudButton {
        faded: root.hudFaded
        locked: root.actionLocked
        label: strings.t("pomodoro.controls.primary").arg("󰑐").arg(strings.t("pomodoro.action.reset"))
        onActivity: root.activity()
        onClicked: root.engine.reset()
      }
      HudButton {
        faded: root.hudFaded
        locked: root.actionLocked
        interactive: root.engine.canSkip
        label: strings.t("pomodoro.controls.primary").arg("󰒭").arg(strings.t("pomodoro.action.skip"))
        onActivity: root.activity()
        onClicked: root.engine.skip()
      }
    }
  }
}

pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// Single source of truth for Zen's visual language.
//
// Colour: a fixed, deep focus surface (this overlay is a theatre-mode layer,
// not a desktop panel) with a small contrast-checked neutral ramp. The one
// chromatic accent comes from the active Omarchy theme and is lifted until it
// clears 4.5:1 against the surface, so a dark theme accent never disappears.
//
// Type: one modular scale derived from the shell's font base size, with no
// decorative tracking. Digits use the user's monospace alias, which is
// tabular by construction — the digits never shift as the timer ticks.
QtObject {
  id: theme

  // ------------------------------------------------------------------ colour
  readonly property color background: "#0b0d10"
  readonly property color surface: "#151a20"
  readonly property color surfaceHover: "#1d242c"

  // 3.32:1 on `background` — a real control boundary, not a decorative hairline.
  readonly property color line: "#5a6673"
  readonly property color lineSoft: "#2b333c"

  readonly property color textPrimary: "#f5f7fa"   // 18.1:1
  readonly property color textSecondary: "#c3ccd6" // 12.0:1
  readonly property color textMuted: "#9aa5b2"     //  7.8:1
  readonly property color accent: readable(Commons.Color.accent, background, 4.5)

  function luminance(c) {
    function lin(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
  }

  function contrast(a, b) {
    var la = luminance(a), lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  // Pull a theme colour toward black or white until it is legible on `bg`.
  function readable(c, bg, minimum) {
    var out = c
    var light = luminance(bg) < 0.18
    var target = light ? Qt.rgba(1, 1, 1, 1) : Qt.rgba(0, 0, 0, 1)
    for (var i = 0; i < 14 && contrast(out, bg) < minimum; i++)
      out = Qt.rgba(out.r + (target.r - out.r) * 0.14,
                    out.g + (target.g - out.g) * 0.14,
                    out.b + (target.b - out.b) * 0.14, 1)
    return out
  }

  // -------------------------------------------------------------- typography
  // Style.font.baseSize is the user's text-size setting (12 by default);
  // Style.fontScale expresses it as a ratio so the whole HUD grows together.
  readonly property real fontScale: Style.fontScale

  function px(multiplier) {
    return Math.max(10, Math.round(12 * multiplier * fontScale))
  }

  readonly property int caption: px(1.0)    // 12
  readonly property int label: px(1.17)     // 14
  readonly property int body: px(1.33)      // 16
  readonly property int heading: px(1.5)    // 18
  readonly property int title: px(1.75)     // 21

  // The hero digits are sized from the screen, capped, and only partly scaled
  // by the user's text setting so a large font cannot overflow the viewport.
  function heroSize(availableWidth) {
    return Math.min(availableWidth * 0.15, 240) * Math.min(fontScale, 1.35)
  }

  // ----------------------------------------------------------------- spacing
  function space(px) { return Style.space(px) }
  readonly property int pageMargin: space(44)
  readonly property int radius: Math.min(Style.cornerRadius, 6)
  readonly property int duration: Style.duration(140)
}

pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// The only text component Zen uses. `role` picks a step on the type scale and
// `tone` picks a contrast-checked colour; callers override `size` or
// `font.weight` only for the hero numerals and the active control label.
Text {
  id: root

  property string role: "body"    // caption | label | body | heading | title | hero
  property string tone: "primary" // primary | secondary | muted | accent
  property real size: 0

  ZenTheme { id: theme }

  textFormat: Text.PlainText
  renderType: Text.NativeRendering
  font.family: Style.font.family
  font.pixelSize: root.size > 0 ? root.size : sizeFor(root.role)
  font.weight: root.role === "hero" ? Font.Light
    : (root.role === "title" || root.role === "heading" ? Font.DemiBold : Font.Normal)
  // No decorative tracking: it hurts small-text legibility and reads as decor.
  font.letterSpacing: 0
  color: {
    if (root.tone === "secondary") return theme.textSecondary
    if (root.tone === "muted") return theme.textMuted
    if (root.tone === "accent") return theme.accent
    return theme.textPrimary
  }

  function sizeFor(r) {
    switch (r) {
      case "caption": return theme.caption
      case "label":   return theme.label
      case "heading": return theme.heading
      case "title":   return theme.title
      case "hero":    return Math.round(200 * theme.fontScale)
      default:        return theme.body
    }
  }
}

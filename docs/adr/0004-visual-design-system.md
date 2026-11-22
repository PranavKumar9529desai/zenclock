# 4. Visual design system: type scale and contrast-checked tokens

We replaced the per-view hardcoded colours and arbitrary font sizes with one
token module (`ZenTheme.qml`) and one text component (`ZenText.qml`).

## Context

The first overlay looked like a generic generated UI: floating pills, bordered
badges, icon-prefixed headings, several hint rows, and a hardcoded cyan that
clashed with the active Omarchy theme. Measurements showed real accessibility
problems too: hint text `#55555f` on `#08080a` was **2.72:1** (WCAG AA needs
4.5:1) and control borders `#2a2a34` were **1.41:1** (non-text UI needs 3:1).
Type was a set of unrelated sizes (13/14/16/18/20/280px) with 2–4px of tracking
on nearly every label.

## Decision

1. **One token source.** `ZenTheme.qml` owns the focus surface, a four-step
   neutral text ramp, the control boundary, spacing, radius, and the type scale.
   All sizes derive from `Style.font.baseSize`, so the shell's text-size setting
   scales the whole HUD.
2. **Contrast first.** Text tokens measure 18.1:1, 12.0:1 and 7.8:1 on the
   surface; the control boundary measures 3.3:1. The one chromatic accent comes
   from `Commons.Color.accent` and is lifted toward white until it clears 4.5:1,
   so a dark or low-contrast theme accent never disappears.
3. **One typography component.** `ZenText.qml` maps `role` to a scale step
   (`caption`, `label`, `body`, `heading`, `title`, `hero`) and `tone` to a colour.
   Tracking is zero everywhere: it hurts small-text legibility and reads as
   decoration. Hero digits use the user's monospace alias, whose tabular figures
   keep the clock and timers from shifting as they tick.
4. **Flat composition.** Mode tabs and timer presets are labels with an active
   rule rather than rounded pills; Pomodoro progress is a row of bars; the
   timezone is plain text; each view has one contextual hint line. No gradients,
   glows, glass, or card grids.
5. **Sentence-case copy.** Uppercase labels with wide tracking were replaced
   with sentence case in `i18n/en.json`.

## Sources

- [WCAG 2.2 SC 1.4.3 Contrast (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
- [WebAIM: Contrast and colour accessibility](https://webaim.org/articles/contrast/)
- [10 Principles for Typography in UI Design](https://uxdesign.cc/10-principles-for-typography-usage-in-ui-design-a8f038f43ffd)
- [AI slop UI: why generic AI design happens](https://smoothui.dev/blog/ai-design-slop)

## Consequences

- Adding a view means picking a `role`/`tone`, not inventing a hex code and font
  size; contrast and scale stay consistent as the HUD grows.
- The focus surface is intentionally a fixed deep neutral, independent of the
  desktop theme. Only the accent follows the theme. A future light-mode design
  would need a different surface/text pair rather than a token tweak.
- The unused i18n keys for the old per-view hints were removed; any translation
  added later must use `hint.clock` / `hint.active`.

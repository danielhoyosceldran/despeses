# CLAUDE.md

## Layout & style documentation

Two living reference docs, kept split by concern:

- **[LAYOUT.md](LAYOUT.md)** — layout and UI element structure of every screen
  (the "what's on screen"). Structure only: **no** visual style (no colors,
  fonts, radii, spacing values).
- **[STYLE.md](STYLE.md)** — the visual-style system (the "how it looks"): color
  tokens, typography, shape/radii, elevation, motion, and per-component
  treatment. Style only: **no** screen structure.

**Rule — update these in the same change that alters them:**

- Whenever you change a screen's layout or element structure (add/remove/reorder
  sections, elements, FAB, header/app-bar contents, panels, sheets, dialogs, nav
  rows, or add/remove a screen), **update the matching section in LAYOUT.md.**
  Keep it style-free.
- Whenever you change a visual token, a theme entry, or the styling of a shared
  widget/component (color, typography, radius, shadow, motion), **update the
  matching section in STYLE.md.** Keep it structure-free.

If a change touches both (e.g. a new styled component on a screen), update both
files.

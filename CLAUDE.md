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

## App philosophy

App tracks monthly expenses/savings and gives some global overview — **not**
a mirror of bank account or user's real net worth/patrimony. Don't design
features assuming real account balance reconciliation.

Sign convention: gastos (expenses) and ahorros (savings) subtract; ingresos
(income) and reembolsos (refunds) add.

## Haptics

The user's **Haptics** setting (`profile.hapticsEnabled`, editable on Account ›
Profile) globally enables/disables vibration.

**Rule — every vibration MUST go through `HapticsService`**
(`lib/core/haptics/haptics.dart`, read it via `hapticsProvider`). It gates each
call on the setting, so when Haptics is off nothing vibrates. **Never call
`HapticFeedback` (or any platform vibration API) directly** anywhere else in the
app — always route feedback through `ref.read(hapticsProvider)`.

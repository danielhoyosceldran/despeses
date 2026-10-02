# CLAUDE.md

## Language

Respond to prompts in castellano (Spanish). Code and comments always in English.

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

**Ahorro is not spending.** The `ahorro` type records money set aside as *not
available* this month — it subtracts from what's left, but it is **not** a
gasto. Don't count it as spent/consumption and don't model it as a fund
balance: there are no savings withdrawals and no running savings balance.
Tracking real patrimony (balances, withdrawals) may come in the future
(backlog BL-037), but is **out of scope for now** — don't design for it.

**Refunds and category budgets.** Categories are per transaction type, so a
refund can never carry an expense category. Budgets by category therefore do
**not** subtract refunds (by design, decision BL-009 option b); budgets by
tag/project/event do. Don't "fix" this by letting refunds use expense
categories.

**Single currency.** Multi-currency is permanently out of scope.

## Database schema baseline

Schema **v9** is the baseline every install starts from
(`AppDatabase.baselineSchemaVersion`). `onUpgrade` has no steps below it and
refuses older files. Read **[docs/database_baseline.md](docs/database_baseline.md)**
before touching `schemaVersion`, `onUpgrade` or `tables.dart`.

## Haptics

The user's **Haptics** setting (`profile.hapticsEnabled`, editable on Account ›
Profile) globally enables/disables vibration.

**Rule — every vibration MUST go through `HapticsService`**
(`lib/core/haptics/haptics.dart`, read it via `hapticsProvider`). It gates each
call on the setting, so when Haptics is off nothing vibrates. **Never call
`HapticFeedback` (or any platform vibration API) directly** anywhere else in the
app — always route feedback through `ref.read(hapticsProvider)`.

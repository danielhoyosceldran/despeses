# Style

Visual-style reference for the whole app: color, typography, shape, elevation,
motion and per-component treatment. Structure/layout lives in `LAYOUT.md` — this
file is style **only** (the "how it looks", not the "what's on screen").

> Keep this file current: whenever you change a visual token, a theme entry, or
> the styling of a shared widget/component, update the matching section here in
> the same change. See CLAUDE.md.

The design is a **mono-ink minimalist** system adapted from the "Innovative
Style Proposal" mock (React + Tailwind v4). Character: near-black/near-white ink
accent (no brand hue), two-tier typography (Inter + Clash Display), soft large
radii, translucent hairline borders as the dominant divider, subtle muted fills,
and motion treated as part of the style. Live color is reserved for money and
data (chart slices, budget bars, icon chips) — never for UI surfaces.

Everything is theme-aware (light + dark). Colors are read through
`ThemeExtension`s via `context.appColors` / `context.semanticColors`, never by
branching on brightness at the call site.

---

## 1. Color — `lib/core/theme/app_colors.dart`

### 1.1 `AppColors` (neutral UI roles)

| Field | Role | Light | Dark |
|---|---|---|---|
| `bg` | scaffold background | `#FFFFFF` | `#0D0D0D` |
| `surface` | cards, sheets, nav, dialogs | `#FFFFFF` | `#161616` |
| `surfaceAlt` | muted fill base | `#ECECF0` | `#262626` |
| `border` | full hairline (nav/sheet frame) | `0x1A000000` (black 10%) | `#2E2E2E` |
| `divider` | border at 50% | `0x0D000000` (black 5%) | `0x802E2E2E` |
| `text` | foreground | `#252525` | `#FAFAFA` |
| `textMuted` | secondary text | `#717182` | `#B5B5B5` |
| `textDisabled` | disabled / drag handle | `#B0B1BC` | `#7F7F7F` |
| `accent` | primary (ink) | `#030213` | `#FAFAFA` |
| `onAccent` | content on accent | `#FFFFFF` | `#161616` |
| `shadow` | frame/FAB/sheet shadow | `0x1F000000` (12%) | `0x99000000` (60%) |

- **`accent` inverts**: near-black ink in light, near-white in dark. It drives
  the FAB, primary button, active nav tab, and input focus ring. `onAccent` is
  its inverse for content sitting on accent fills.
- `border` stays **translucent** (real alpha) so the 50% hairline reads over any
  surface — do not flatten it against a solid color.

### 1.2 Helpers (on `AppColors`)

- `borderSoft` → `border` at 50% alpha. The default divider for card outlines,
  row separators, stat tiles, transaction rows, inputs.
- `mutedFill([opacity = 0.3])` → `surfaceAlt` at the given alpha. Used at **0.30**
  (stat tiles, form fields), **0.50** (segmented track, search pill), **0.80**
  (active nav pill).

### 1.3 Semantic colors — `AppSemanticColors` (same in both themes)

| Field | Value | Notes |
|---|---|---|
| `income` | emerald `#10B981` | |
| `expense` | rose `#F43F5E` | |
| `refund` | amber `#F59E0B` | **fallback only** — refund renders in neutral `text` |
| `savings` | blue `#3B82F6` | `ahorro` type — money set aside, not spent |
| `over` | rose `#F43F5E` | over-budget bar/percentage |

Amount color by type: `context.amountColorForType(type)` → income = emerald,
expense = rose, **refund = neutral `text`** (per the mock, no dedicated hue),
savings (`ahorro`) = blue.

### 1.4 Data-accent palette — `AppDataColors` (Tailwind 500)

`emerald #10B981 · rose #F43F5E · purple #8B5CF6 · amber #F59E0B · blue #3B82F6`.
Used **only** for category icon chips, budget progress fills, and donut slices —
never as a UI surface fill. `AppDataColors.cycle` = `[emerald, purple, amber,
blue, rose]` for auto-assigning series colors.

### 1.5 Chip fills

- `iconChipBackground(color)` → data color at **10%** (icon-chip background, icon
  in full color). E.g. income chip = emerald @10% behind an emerald icon.
- `pillBackground(color)` → color at **15%** (selection/chip UI treatment).

---

## 2. Typography — two tiers (`app_theme.dart`)

Two families:
- **Inter** — UI/body. Default `fontFamily`. Weights 400/500/600 (medium is the
  predominant UI weight).
- **Clash Display** — money, headlines, section titles, budget names, modal
  titles. Bundled from Fontshare (`assets/fonts/ClashDisplay-*.ttf`, weights
  300/400/500/600). Not on Google Fonts.

### 2.1 `appDisplay(colors, {required fontSize, fontWeight = w500, color})`
Clash Display, `letterSpacing -0.5` (tracking-tight), `height 1.0`, **tabular
figures**. The single source for every money/headline style — use it directly
for amounts that aren't a named `TextTheme` slot.

### 2.2 `appHeaderStyle(colors, {fontSize = 12})`
Inter w600, `letterSpacing 0.5`, `textMuted`. Uppercase section/day headers
(apply `.toUpperCase()` at the call site).

### 2.3 `TextTheme`

| Slot | Family / size / weight | Use |
|---|---|---|
| `displayLarge` | Clash 60 w500 | balance hero (expanded) |
| `displayMedium` | Clash 48 w500 | analytics total |
| `displaySmall` | Clash 34 w500 | keypad / big totals |
| `headlineMedium` | Clash 28 w500 | `PageTitleHeader` |
| `headlineSmall` | Clash 22 w500 | `AppTopBar` title |
| `titleLarge` | Clash 20 w500 | display section titles |
| `titleMedium` | Inter 17 w500 h1.5 | selection count, field labels |
| `labelLarge` | Inter 15 w500 h1.5 | row/tile titles |
| `bodyMedium` | Inter 15 w400 h1.5 | body text |
| `bodySmall` | Inter 13 w400 h1.5 muted | subtitles / secondary |
| `labelSmall` | Inter 12 w500 muted | small labels |

Rules: every amount carries tabular figures; display slots use Clash Display at
`height 1.0`; Inter slots use `height 1.5`. Predominant UI weight is 500.

---

## 3. Shape, radii & borders — `app_dimens.dart`

| Token | Value | Use |
|---|---|---|
| `radiusCard` | 16 | cards, stat tiles, transaction rows, inputs, buttons |
| `radiusPanel` | 24 | large panels (`AppCard.large`): analytics card, settings card |
| `radiusBudget` | 12 | budget card (slightly tighter) |
| `radiusSheet` | 40 | top corners of bottom sheets / `BottomActionPanel` |
| `radiusButton` | 16 | primary full-width button |
| `radiusPill` | 100 | FAB, search pill, icon buttons, progress bars, chips, avatars |

Segmented control uses a bespoke radius **14** (container). Nav pill uses
`radiusButton` (16).

Borders: **hairline `borderSoft` (border/50)** is the default divider — card
outlines, stat tiles, transaction rows, inputs, settings row separators. Full
`border` only on the nav bar top edge and sheet top edge. Input focus = 1.5px
`accent` ring.

### Spacing scale — `AppSpacing`
`xs 4 · sm 8 · smMd 12 · md 16 · lg 24 · xl 32 · xxl 48 · xxxl 64`. Space is the
primary separator; borders appear only where space alone isn't enough.

### Shadows — `AppShadows`
One soft shadow, reserved for elevated things (cards rely on the hairline
instead):
- `card` — blur 24, offset (0, 8).
- `fab` — blur 20, offset (0, 8).
- `sheet` — blur 40, offset (0, −8).
All use `colors.shadow` (pre-baked opacity per theme).

---

## 4. Component themes (`app_theme.dart` `_build`)

- **Global**: Material 3, `scaffoldBackgroundColor = bg`, `fontFamily = Inter`,
  no splash (`NoSplash` + transparent highlight), `dividerColor = divider`.
- **AppBar**: transparent, no elevation, `foregroundColor = text` (only entry
  screens and pushed sub-screens still use a Material AppBar; tab screens use the
  in-body `AppTopBar`).
- **Card / Dialog**: `surface`, elevation 0, radius 16 (card) / 16 (dialog).
- **Bottom sheet**: `surface`, elevation 0, drag handle in `textDisabled`, top
  radius 40.
- **NavigationBar theme** (values still referenced, though the shell renders a
  custom bar): transparent indicator, label Inter 10 w500, icon size 22, active
  = `accent` / inactive = `textMuted`.
- **Input**: filled `mutedFill(0.30)`, no border, focus 1.5px `accent` ring,
  radius 16, hint in `textMuted`.
- **FilledButton** (primary): `accent` bg / `onAccent` fg, height 56, elevation
  0, Inter 18 w500, radius 16.
- **TextButton**: `accent` foreground.
- **SegmentedButton**: track `mutedFill(0.5)`, selected segment `surface`, text
  Inter 14 w500, active `text` / inactive `textMuted`, container radius 14.
- **Track cell** (budget entry Tracks 2×2 grid): 48-high toggle, `radiusBudget`
  (12); selected = `accent` fill + `accent` border + `onAccent` w600 text,
  unselected = `surface` fill + `border` + `text` w400; disabled `textDisabled`.
  Selection transition `animFast`/`animCurve`.
- **Chip**: `surfaceAlt` bg, selected `pillBackground(accent)`, pill radius, no
  border.
- **Switch**: default Material 3 track; `activeThumbColor = accent` (set at call
  sites, e.g. the Profile Feedback/Haptics toggle — not yet globally themed).
- **SnackBar**: `surfaceAlt`, radius 16, elevation 0.
- **ProgressIndicator**: `accent` on `surfaceAlt` track.
- **FAB**: `accent` / `onAccent`, elevation 0, `CircleBorder` (shadow +
  scale-on-press come from the wrapper, not the theme).

---

## 5. Shared-widget styling

- **`AppCard`** (`app_card.dart`) — `surface`, hairline `borderSoft`, radius 16.
  `AppCard.large` = radius 24 (analytics panel, settings card). No shadow by
  default (hairline carries it).
- **`AppTopBar`** (`app_top_bar.dart`) — in-body header, `SafeArea` top,
  `px = lg`, content height 44. Month label: Inter 14 w500 uppercase `textMuted`.
  Title: `headlineSmall` (Clash 22).
- **`TopBarCircleButton`** — circular header action. Ghost (transparent, muted
  icon) for chevrons/actions; `filled` (`surfaceAlt` chip, `text` icon) for the
  settings gear. Icon 20, `sm` padding. Optional `color` override (e.g. `accent`
  when a filter is active).
- **Search pill** (budgets `_SearchPill`) — `TextField`, `mutedFill(0.5)` fill,
  `radiusPill`, leading `search` icon 16 muted, `bodyMedium` text, focus 1px
  `accent` ring. Paired with a ghost `archive` `TopBarCircleButton` (accent tint
  when showing archived/expired).
- **`ThinProgressBar`** (`thin_progress_bar.dart`) — 6px tall, track
  `surfaceAlt`, solid `fillColor` (data color / `over` when over budget),
  rounded-full.
- **Transaction row** (dashboard `_ExpenseRow`, expenses `_ExpenseTile`) —
  hairline card radius 16 on `surface` (`mutedFill(0.5)` when selected). Left
  column: uppercase category line (Inter 11 w500, `letterSpacing 0.5`, muted) +
  title (`labelLarge`). Right: signed amount in Clash 18 via
  `amountColorForType` (income `+`, refund `±`, expense `-`).
- **Stat tile** (dashboard hero) — `mutedFill(0.30)`, radius 16, hairline; 32px
  icon chip (`iconChipBackground`) + `labelSmall` label + Clash 20 value.
  Income = emerald `arrowDownRight`, Spent = rose `arrowUpRight`.
- **Budget tile** — name `labelLarge`, `ThinProgressBar`, `spent / limit` in
  `bodySmall` tabular (`over` color when exceeded).
- **Recurring-due tile** (`_RecurringDueTile`) — hairline card radius 16 on
  `surface`, `minHeight 60`. Default face: name (`labelLarge`) left, signed
  amount in Clash 16 via `amountColorForType` right (no category line). Armed face (160ms
  `AnimatedSwitcher` cross-fade): two full-height halves split by a `borderSoft`
  hairline — reject ✕ (`semantic.expense`) left, accept ✓ (`semantic.income`)
  right, each on a `pillBackground` tint of its color. Empty grid slot reuses the
  budget placeholder (`surfaceAlt` @ 0.4). Section tail link = `accent` "Review"
  label + chevron.
- **`PressableScale`** (`pressable_scale.dart`) — scale-on-press wrapper (0.95,
  120ms, easeOutCubic); wraps the FAB.
- **Day-group header** (dashboard) — `appHeaderStyle` uppercase label +
  signed day total (`labelSmall` tabular; ≥0 emerald, <0 muted).

---

## 5b. Analytics charts (`widgets/charts/`)

Data-viz surface for the Analytics screen. Live color only on data; frames/UI
stay ink/neutral.
- **Section tab strip** — pill chips (`radiusPill`). Selected = `accent` fill /
  `onAccent` text; unselected = transparent with `borderSoft`. Preferred
  sections (Categories, Tags) carry a `savings`-tinted border + star icon.
- **`DonutChart`** — `fl_chart` donut, `centerSpaceRadius 60`, `sectionsSpace 5`,
  slice radius 20, colors from `AppDataColors.cycle`; optional center widget
  (total in `appDisplay`). Tap a `drillable` slice to drill.
- **`StatCard`** — `AppCard` (hairline, `radiusCard`) with a `labelLarge` title,
  optional muted `bodySmall` subtitle (the stat's Excel ref), then the chart.
- **`KpiTile`** — `mutedFill(0.30)` fill, hairline, `radiusCard`; `appHeaderStyle`
  label + `appDisplay` 22 value (accent color for at-risk/emphasis).
- **`MonthlyBars` / `TrendLines`** — bars use `accent` (or a semantic/data color);
  lines 2.5px, curved, no dots; moving-average line uses `savings` blue.
- **`RingGauge`** — `CircularProgressIndicator` 10px on `surfaceAlt` track,
  fill `accent` or a semantic color; percent centered in `appDisplay`.
- **`CalendarHeatmap`** — 7-col grid; empty day = `surfaceAlt`, else base color at
  `0.15 + 0.85·intensity` alpha; `radius 4` cells.
- **`RankedList` / `LegendRow`** — proportional `LinearProgressIndicator` /
  color-dot rows; amounts in tabular figures.
- **`StatInfoButton`** — compact `IconButton` (`info300`, 18px, `textMuted`,
  32×32 tap target) placed beside a stat's title. Opens `showStatInfoSheet`: a
  `showDragHandle`/`isScrollControlled` bottom sheet with `titleMedium` (bold)
  title, `bodyMedium` explanation, and an optional example widget below.

## 6. Iconography — lucide

`lucide_icons_flutter`, thin-line weight (the `*300` variants). Sizes: nav 22,
FAB 24, list/header icons 18–20, inline 16. Default tint `textMuted`; active /
primary `accent` (or `text`). Bottom-nav: Dashboard `layoutDashboard`, Expenses
`receipt`, Budgets `pieChart`, Analytics `barChart2`, Settings/catalog `layers`.
Header gear `settings`.

---

## 7. Motion

- **Route transition** (`_SlideFadeTransitionsBuilder`) — fade + horizontal
  slide (x 0.05→0), `easeOutCubic`.
- **Edit entry route** (`bottomUpRoute`) — full vertical slide (y 1→0), in
  320ms `easeOutCubic` / out 260ms `easeInCubic`; dismisses back down. Used when
  editing an existing expense/budget (tapping a list row).
- **Interactive add sheet** (`DragUpAction`, shown via an `OverlayEntry` — not a
  pushed route, because pushing mid-drag cancels the gesture) — the add FAB is
  the motor. On drag-up the **FAB follows the finger 1:1** (chases at 0ms, eases
  home 220ms on release). After a 72px arm threshold a `medium` haptic confirms
  and the entry screen starts rising, tracking finger travel *beyond* the
  threshold (`(dragPx − 72) / (height − 72)`) so it trails the finger. Release
  past the threshold (or fling up ≥700px/s) completes the open (`animateTo 1`,
  300ms `easeOutCubic`); release below cancels and slides it back down (220ms
  `easeInCubic`). Tap plays the same open animation. The sheet closes via an
  `onClose` callback (Android back intercepted by `BackButtonListener`).
- **Tab switch** (`app_shell`) — `AnimatedSwitcher` 280ms, slide (0.06→0) + fade,
  in `easeOutCubic` / out `easeInCubic`.
- **Nav pill** (`app_shell` `_NavBar`) — `AnimatedPositioned` pill
  (`mutedFill(0.8)`, radius 16) slides behind the active tab, 300ms easeOutCubic.
- **Dashboard balance collapse** (`dashboard_screen` `_HeroHeaderDelegate`) — a
  pinned `SliverPersistentHeader` whose `shrinkOffset` maps 1:1 to `t` (0→1)
  between `minExtent 88` and `maxExtent 244`. As `t` grows the balance shrinks
  (Clash 60→30), the Income/Spent tiles fold away (`Align(heightFactor: 1-t)` +
  `Opacity(1-t)`), padding tightens, and a hairline bottom border fades in. The
  scroll **is** the animation clock — no timed controller.
- **FAB press** — `PressableScale` (see §5).
- **Analytics section-FAB drag** (`analytics_screen` `_SectionFab`) — dragging
  the section FAB gives live feedback along the committed axis: the button
  follows the finger (`Transform.translate`, clamped ±20px, vertical or
  horizontal) and, once past the ±24px arm threshold, scales to 1.12 with
  elevation 12 (`AnimatedScale`/elevation, 120ms easeOut) while its icon
  cross-fades (`AnimatedSwitcher`, scale+fade, 120ms) to the **target**
  section's icon — preview of where release lands. Vertical steps one section
  (up/down); horizontal-left toggles the two preferred sections. Cancel resets.
  While armed, a centred floating preview card (`_SectionPreviewCard`) fades +
  scales in (`AnimatedSwitcher`, 140ms, 0.9→1) over the body showing the target
  section's icon (40) + name: `surface` fill (auto light/dark), hairline
  `borderSoft`, `radiusPanel` 24, `AppShadows.card`.
- **Motion tokens** (`AppDimens`): `animFast 200ms`, `animNormal 300ms`,
  `animCurve easeOutCubic`.

---

## 8. Scope / conventions

- Never encode style as magic numbers at call sites — add or reuse a token
  (`AppColors`, `AppSemanticColors`, `AppDataColors`, `AppDimens`, `AppSpacing`,
  `AppShadows`) or a `TextTheme` slot.
- Live/data color only on money and data viz; UI surfaces stay ink/neutral.
- Both themes must be handled — go through the `ThemeExtension`s.
- Code comments in English.

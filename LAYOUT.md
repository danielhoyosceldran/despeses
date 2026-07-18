# Layout & Screens

Structural reference for every screen: layout and UI elements only — **no visual style** (no colors, fonts, spacing).

> Keep this file current: whenever a screen's layout or element structure changes, update the matching section here. See CLAUDE.md.

## Navigation shell

`AppShell` — `NavigationBar` (bottom) with 5 tabs: **Dashboard · Expenses · Budgets · Analytics · Settings**. The Settings tab holds the data catalog (categories, tags, …). Expenses tab is behind a feature flag. Horizontal drag on the nav bar switches tabs. Tab change is instant (the shell's IndexedStack); no body transition — animating the shell itself duplicates its GlobalKey. Root route intercepts system back: requires a second back press within 2s to exit (toast on first press).

The header gear (`AppTopBar`) opens a separate **Account** hub (Profile · Export · Backup) pushed over the shell — distinct from the Settings tab.

---

## Shared widgets (referenced by role)

| Widget | Layout it provides |
| --- | --- |
| `PageTitleHeader` | Large in-body title Row: title left, optional trailing action right. Used where AppBar is title-less. |
| `AppTopBar` | Shared in-body top header (no Material AppBar). Left: month pager (chevron · uppercase month/year · chevron, emits month ±1) **or** a display title. When given the page's `PageController`, the month label tracks the swipe continuously (sliding filmstrip revealing the incoming month) instead of flipping on settle. Trailing: optional actions (`TopBarCircleButton`s) then a settings gear that pushes the Account hub. In selection mode swaps to: leading X (clear) · "N selected" · trailing trash (delete). Settings gear hideable. |
| `TopBarCircleButton` | Circular header action (ghost or filled chip); used for chevrons, gear, and per-screen actions (filter, active/expired eye). |
| `BottomActionPanel` | In-screen animated bottom panel (not modal). Height 0→content, rounded top. Hosts keypad/pickers. |
| `NumericKeypad` | 4×56 money keypad. 3 digit columns (`1/4/7/00`, `2/5/8/0`, `3/6/9/,`) + 4th column: backspace, `-`, large "Next". |
| `ExpenseFilterSheet` | Modal sheet. Column: "Filters" title, 6 dropdowns (Type, Category, Tag, Payment method, Event, Project), From/To date Row, "Clear"/"Apply" Row. |
| `CategoryPickerSheet` / `...Content` | Drill-down picker (modal 70% or embedded). Optional breadcrumb back-row + ListView of grid rows (64px ancestor cells + wide candidate cell). Leaf selects; branch descends. |
| `SimplePickerSheet` / `...Content` | Single-select (modal 60% or embedded). Title + ListView of ListTiles; tap selects & closes. |
| `TagPickerSheet` / `...Content` | Grouped multi-select (modal 70% or embedded). Group label + Wrap of FilterChips per group. Confirmed via external "Next". |
| `EntityListTile` | CRUD row. Dismissible (swipe-right edit, swipe-left delete-confirm): leading avatar, title + optional subtitle, optional trailing chevron, optional inset hairline. |
| `HairlineListTile` | Nav/hub row. Leading tinted icon, title + optional subtitle, trailing chevron, optional inset hairline. |
| `EntityFormDialog` | AlertDialog: Name field, optional Icon field, optional color-swatch Wrap. Cancel/Save. |
| `EventProjectFormDialog` | AlertDialog: Name field, multiline Description field, Start/End date Row. Cancel/Save. |
| `MonthPickerDialog` / `...Content` | Month picker (Dialog 300×340 or embedded). Year stepper Row + 3-col grid of 12 months. |
| `AppCard` | Rounded surface container, configurable padding/margin. |
| `ThinProgressBar` | Thin horizontal progress bar (track + fill). Budget progress. |
| `ErrorRetry` | Centered async-failure placeholder: alert icon, message, outlined "Retry" button. Shown in place of a stuck spinner when a section/month load fails (Analytics sections, Dashboard month). |
| `EmptyState` | Centered "nothing here" placeholder: single centered text line. Shared empty state for Analytics sections and lists. |

---

## Screens

### Dashboard (`dashboard_screen.dart`)
- **Header**: `AppTopBar` in month mode (month pager left, settings gear right). Selection mode (long-press a transaction): "N selected", X (clear), trash (delete-confirm).
- **FAB**: "+" → ExpenseEntryScreen (new). Tap, or drag up to interactively pull the entry screen up from the bottom (finger is the animation motor).
- **Body** Column, top→bottom:
  1. `AppTopBar` — month/year chevron nav + settings gear (shared across months).
  1b. **Recurring banner** (`_RecurringBanner`, shown only when recurring occurrences are pending and not in selection mode): repeat icon + pending-count text + "Review" affordance + chevron. Tap → `/settings/recurring`.
  2. **Balance hero** (`_BalanceHeader`, shared, sits *outside* the PageView): "Total Balance" label + large balance amount, then a Row of 2 collapsing stat tiles (Income · Spent; each = icon chip in a row beside a label + amount column). **Collapses on inner scroll**: balance shrinks, stat tiles fold away, a hairline bottom border fades in.
  3. Expanded horizontal `PageView` of month pages (swipe = month ±1, kept in sync with `MonthHeaderBar`). Each month page is a scrolling `ListView` driving the hero collapse, top→bottom:
     - If active budgets: "Active budgets" header + budget tiles (name, `ThinProgressBar`, spent/limit).
     - Transactions **grouped by day**: per-day header (uppercase day label + signed day total) followed by transaction rows (optional selection Checkbox, uppercase category line, title, method subtitle, signed amount). "No transactions" text when empty. Tap = edit / toggle; long-press = select.
     - On load failure the page body shows `ErrorRetry` instead of the transaction list.

### Expenses (`expenses_screen.dart`)
- **Header**: `AppTopBar` title "Expenses", trailing filter action (tinted when active) → `ExpenseFilterSheet` + settings gear. Selection mode: "N selected", X, trash.
- **FAB**: "+" → ExpenseEntryScreen (new). Tap, or drag up to interactively pull the entry screen up from the bottom (finger is the animation motor).
- **Body**: paginated `ListView` of expense card tiles (optional Checkbox, title, date subtitle, signed amount). Trailing "Load more" TextButton when more pages. Empty/loading centered. Tap = edit/toggle; long-press = select.

### Budgets & Goals (`budgets_screen.dart`)
Two collections behind a `SegmentedButton` toggle (Budgets | Goals).
- **Header**: `AppTopBar` title "Budgets" + settings gear. Selection mode: "N selected", X, trash (deletes from whichever tab is active).
- **Tab toggle** (hidden in selection mode): full-width `SegmentedButton` — Budgets / Goals. Kept in sync with the body `PageView` (tapping animates the page; swiping updates the segment). Switching clears selection.
- **Search row** (fixed, both tabs, hidden in selection mode): search pill (filter the active tab's list by name) + trailing archive toggle. The toggle's meaning follows the tab: active↔expired budgets, or in-progress↔completed goals.
- **FAB**: "+" → BudgetEntryScreen (Budgets tab) or GoalEntryScreen (Goals tab), new. Tap, or drag up to interactively pull the entry screen up from the bottom.
- **Body**: horizontal `PageView` (swipe budgets ↔ goals, mirroring the Dashboard month swipe; disabled in selection mode), two pages:
  - **Budgets**: `ListView` of `AppCard` tiles (optional Checkbox, name, subtitle = `ThinProgressBar` + spent/limit).
  - **Goals**: `ListView` of `AppCard` tiles (optional Checkbox, name + reached check icon, subtitle = `ThinProgressBar` (fills toward target, savings colour when reached) + saved/target + optional "save X/month" pace line when a deadline is set).
  - Both: empty/loading centered; tap = edit/toggle; long-press = select.

### Analytics (`analytics_screen.dart` + `analytics/analytics_sections.dart`)
Sectioned screen navigated by a section FAB.
- **Header**: `AppTopBar` — month mode (month pager) only on month-scoped sections; on non-month sections (Trend, Cash flow, Events) it shows the section title instead of the pager. Settings gear always right.
- **Section FAB**: circular FAB showing the current section's own icon (no label). Tap opens a bottom-sheet menu listing every section, each with its icon (current highlighted with a check). Drag gestures: a **vertical** drag steps sections one at a time (up = next, down = previous); a **horizontal-left** drag toggles between the two **preferred** sections (Categories ↔ Tags). Neither collides with the body's horizontal month swipe (that lives in the PageView). While a drag is armed, a **centred floating preview card** (`_SectionPreviewCard`: target section's icon + name) appears mid-screen over the body. Section order: Categories · Tags · Health · Trend · Cash flow · Payment · Behavior · Quality · Budgets · Events.
- **Body**: a `PageView` — month-scoped sections are swipeable left/right to change month (tracked by the header label + chevrons, mirroring Dashboard); non-month sections (Trend, Cash flow, Events) disable the swipe. Each section is a scrolling `ListView` of `StatCard`s / panels. Time-series sections (Trend, Cash flow) render a `[6M][12M][24M]` `WindowSelector` at the top instead of using month. Each section has three states: loading spinner, `ErrorRetry` on failure, or its data body.
- **Sections**:
  - **Categories / Tags** (preferred): `AppCard.large` donut (`DonutChart`) with the total in the hole; Categories supports drill-down (tap slice/legend → breadcrumb Row with circular back). Legend rows below (`LegendRow`). Leaf-only, so no "direct" slice.
  - **Health**: `KpiTile` grid (savings rate, vs 3M avg, top category, budgets at risk, projection, no-spend streak) + burn-up `TrendLines`.
  - **Trend**: MoM/YoY tiles, monthly `MonthlyBars` + 3M moving-average line, weekday bars, `CalendarHeatmap`.
  - **Cash flow**: net bars, savings-rate `RingGauge`, cumulative balance + cumulative savings lines.
  - **Payment**: spend-by-method `RankedList`.
  - **Behavior**: ticket KPIs, amount histogram, ant-spend, refunds ring.
  - **Quality**: tag-coverage `RingGauge`.
  - **Budgets**: per active budget, progress bar + pace/projection line.
  - **Events**: event dropdown selector + total/€-per-day tiles + spend timeline + out-of-range notice.
- **Shared chart widgets** live in `widgets/charts/` (`DonutChart`, `LegendRow`, `analytics_widgets.dart`: `KpiTile`/`KpiTileGrid`, `RankedList`, `MonthlyBars`, `TrendLines`, `RingGauge`, `CalendarHeatmap`, `StatCard`).

### Settings (`settings_screen.dart`)
Data catalog tab.
- **Header**: `AppTopBar` title "Settings" + gear (→ Account hub).
- **Body**: single `AppCard` Column of `HairlineListTile` nav rows: Recurring, Categories, Tags, Tag groups, Payment methods, Events, Projects. The Recurring row shows a trailing accent count badge when there are pending occurrences.

### Account (`account_screen.dart`)
Personal/app settings hub, pushed over the shell from the header gear.
- **AppBar**: empty (back button).
- **Body**: `PageTitleHeader` "Settings" + single `AppCard` Column of `HairlineListTile` rows: Profile, Export, Backup.

### Expense entry (`expense_entry/expense_entry_screen.dart`)
Full-screen entry; opens by sliding up from the bottom, dismisses sliding down.
- **AppBar**: leading down-chevron (dismiss); centered title = date `TextButton` (opens the calendar panel).
- **Body** Column:
  1. Expanded fields ListView: centered type selector (Expense · Income · Refund · Savings as tappable text separated by "|"; selected takes its colour + bold, clears category on change) · big centered tappable amount (`AmountText`, opens keypad) · Description field (themed filled input, no wrapping card) · `AppCard` of rows [Category · Payment method · Tags (count) · Row [Event | Project]] · multiline Notes field (themed filled input, no wrapping card).
  2. When panel open: inline action Row above panel — full-width "Save", or "Save"+"Next" in tags step.
  3. `BottomActionPanel`: `NumericKeypad` (amount), `CalendarPanel` (shared month nav + 7-col day grid), `CategoryPickerContent`, `SimplePickerContent`, or `TagPickerContent`.
  4. No panel: bottom SafeArea full-width "Save" button.
- Tapping a field row opens its panel. "Next" auto-advances through amount → description → category → payment method, then stops; remaining fields (tags, event, project, notes) are filled manually. Skips empty ref types. Pops `true` on save.
- Can be opened pre-filled from a `ExpenseSeed` (recurring "edit & confirm" flow): all fields hydrated, keypad does not auto-open.

### Budget entry (`budget_entry/budget_entry_screen.dart`)
Full-screen entry; opens by sliding up from the bottom, dismisses sliding down.
- **AppBar**: leading down-chevron (dismiss); title ("New budget" / "Edit budget").
- **Body** Column:
  1. Expanded ListView:
     - **Limit hero**: centered uppercase "LIMIT" header + centered `AmountText` (tap → keypad).
     - **Name** field (themed filled input, no wrapping card).
     - **Tracks** section (uppercase header) — 2×2 grid of toggle cells (Category/Tag/Project/Event, disabled in edit) + `AppCard` value row → picker (disabled in edit).
     - **Period** section (uppercase header):
       - **Category/Tag** dimension — `SegmentedButton` (Monthly/Range, disabled in edit) + conditional:
         - **Monthly**: hint text (recurs every month).
         - **Range**: `AppCard` with From + Until field rows (both required, divider between).
       - **Project/Event** dimension — no picker; period is fixed to the entity's own duration. Read-only `AppCard` (From/Until months) + caption when the entity has dates, else a warning that the event/project needs start/end dates.
  2. Inline "Save" above panel when open.
  3. `BottomActionPanel`: `NumericKeypad`, `MonthPickerContent`, `CategoryPickerContent`, or `SimplePickerContent`.
  4. No panel: bottom SafeArea full-width "Save" button.
- New budget: keypad opens first; "Next" auto-advances amount → name, then stops (dimension, value, period chosen manually). Pops `true` on save.

### Goal entry (`goal_entry/goal_entry_screen.dart`)
Full-screen entry; opens by sliding up from the bottom, dismisses sliding down. Creates/edits a savings goal.
- **AppBar**: leading down-chevron (dismiss); title ("New goal" / "Edit goal").
- **Body** Column:
  1. Expanded ListView:
     - **Target hero**: centered uppercase "TARGET" header + centered `AmountText` (tap → keypad).
     - **Name** field.
     - **Savings category** section (uppercase header) — `AppCard` value row → `ahorro`-scoped category picker (locked in edit).
     - **Deadline** section (uppercase header) — `AppCard` row → calendar panel; shows "No deadline" placeholder with a trailing clear button when set.
  2. Inline "Save" above panel when open.
  3. `BottomActionPanel`: `NumericKeypad`, `CategoryPickerContent` (ahorro tree), or `CalendarPanel` (deadline).
  4. No panel: bottom SafeArea full-width "Save" button.
- New goal: keypad opens first; "Next" moves amount → name. Category + currency lock after creation; only name/target/deadline stay editable. Pops `true` on save.

### Recurring entry (`recurring/recurring_entry_screen.dart`)
Full-screen entry; opens by sliding up from the bottom, dismisses sliding down. Creates/edits a recurring-transaction template. Every field editable in both new and edit modes.
- **AppBar**: leading down-chevron (dismiss); centered title ("New recurring" / "Edit recurring").
- **Body** Column:
  1. Expanded ListView: centered type selector (Expense · Income · Refund · Savings) · big centered tappable amount (`AmountText`, opens keypad) · Description field · **Schedule** section (uppercase header): `SegmentedButton` (Monthly/Weekly/Yearly) + `AppCard` with Starts row and Ends row (Ends shows "No end date" placeholder with a trailing clear button when set) · **Details** section (uppercase header): `AppCard` of rows [Category · Payment method · Tags (count) · Row [Event | Project]] · multiline Notes field.
  2. Inline "Save" above panel when open ("Save"+"Next" in tags step).
  3. `BottomActionPanel`: `NumericKeypad`, `CalendarPanel` (start/end date), `CategoryPickerContent`, `SimplePickerContent`, or `TagPickerContent`.
  4. No panel: bottom SafeArea full-width "Save" button.
- New: keypad opens first; "Next" moves amount → description. Save requires amount > 0 + non-empty description + end date not before start. Pops `true` on save (then materializes any already-due dates).

### Settings › Recurring (`recurring/recurring_screen.dart`)
- **Header**: `AppTopBar` title "Recurring". Selection mode (long-press a template): "N selected", X (clear), trash (delete-confirm).
- **FAB**: "+" → RecurringEntryScreen (new). Tap, or drag up to interactively pull it up from the bottom.
- **Body** `ListView`, two stacked sections:
  - **Pending** (only when occurrences await confirmation): uppercase "PENDING" header with a "Confirm all" TextButton when >1, then one `_PendingCard` per occurrence — description + due date + amount, with Skip / Edit / Confirm actions. Confirm → creates the real transaction; Edit → opens the seeded `ExpenseEntryScreen`; Skip → discards. Actions show a toast.
  - **Templates**: uppercase "TEMPLATES" header, then one `_TemplateCard` per template (name, subtitle = frequency + next date, or "Paused"; trailing amount + active `Switch`). Tap = edit; long-press = select. `EmptyState` when none.

### Account › Backup (`settings/backup_screen.dart`)
- **AppBar**: empty.
- **Body**: `AppCard` Column of 2 `HairlineListTile`: "Export backup" (spinner trailing while busy) + "Restore backup". Export → share sheet; Restore → file picker + destructive confirm + toast.

### Account › Export (`settings/export_screen.dart`)
- **AppBar**: empty.
- **Body** ListView: From | To date TextButtons Row · "Type" dropdown (All/Expense/Income/Refund) · "Export CSV" button · "Export PDF" button · `LinearProgressIndicator` while busy. Both exports build rows → share sheet.

### Account › Profile (`settings/profile_screen.dart`)
- **AppBar**: empty.
- **Body** ListView: `PageTitleHeader` "Profile", then three labeled sections, each a section label above an `AppCard`: **Language** — one option row per locale (native name + trailing check on the selected one); **Theme** — three option rows (Light / Dark / System, trailing check on the selected one); **Currency** — single read-only `HairlineListTile` (coins icon) with the currency code as trailing text; **Feedback** — a single toggle row (label + trailing `Switch`) for Haptics.

### Settings › Events (`settings/events_screen.dart`)
- **AppBar**: empty.
- **Body** Column: `PageTitleHeader` "Events" + Expanded `ListView` of `EntityListTile` (title = name, subtitle = description).
- **FAB**: "+" → `showEventProjectFormDialog` (new). Swipe edit/delete (delete confirm warns of dependent budgets).

### Settings › Projects (`settings/projects_screen.dart`)
Identical to Events with "Projects" title.

### Settings › Categories (`settings/categories_screen.dart`)
- **AppBar**: empty.
- **Body** Column: at root, `PageTitleHeader` "Categories" + a full-width `SegmentedButton` (Expense / Income / Refund / Savings) that switches which per-type category tree is shown; when drilled, a breadcrumb Row (circular back + path) replaces both · Expanded `ReorderableListView` of `EntityListTile` (long-press drag reorder; tap descends into children; swipe edit/delete).
- **FAB**: "+" → `showEntityFormDialog`, hidden at depth ≥ 3 (max 3 levels). New categories are created in the currently selected type's tree.

### Settings › Tag groups (`settings/tag_groups_screen.dart`)
- **AppBar**: empty.
- **Body** Column: `PageTitleHeader` "Tag groups" + Expanded `ReorderableListView` of `EntityListTile`. "Ungrouped" group has edit/delete disabled.
- **FAB**: "+" → `showEntityFormDialog` (name only). Delete moves tags to Ungrouped.

### Settings › Payment methods (`settings/payment_methods_screen.dart`)
Same as Tag groups: `PageTitleHeader` "Payment methods" + reorderable `EntityListTile` list (icon, no color). FAB "+" → `showEntityFormDialog` (with icon).

### Settings › Tags (`settings/tags_screen.dart`)
- **AppBar**: empty.
- **Body** Column: `PageTitleHeader` "Tags" + Expanded outer `ListView`, one section per tag group. Each section: group header Row (name + trailing "+" to add tag to group) above a nested non-scrolling `ReorderableListView` of `EntityListTile` (reorder within group; swipe edit/delete). No FAB.

---

## Cross-screen patterns
- Tab screens (Dashboard, Expenses, Budgets, Analytics, Settings) have no Material `AppBar`; they render a shared in-body `AppTopBar` (month pager or title + settings gear) and, where they create, a `FloatingActionButton`. Entry screens still use a real Material `AppBar`. All `settings/*` list screens leave the AppBar empty and render their title via `PageTitleHeader`.
- Selection mode (multi-delete) on Dashboard, Expenses, Budgets (both tabs), Recurring swaps `AppTopBar` contents (count + clear + delete).
- Entry screens (expense/budget/goal/recurring) use the in-screen `BottomActionPanel` + `NumericKeypad` + embedded pickers, not modal sheets. The Expenses list uses a true modal filter sheet.
- Recurring (reached from the Settings hub, but not a `settings/*` list screen) renders an `AppTopBar` + FAB like a tab screen, rather than the `PageTitleHeader` used by the catalog list screens.

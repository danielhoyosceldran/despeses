# Layout & Screens

Structural reference for every screen: layout and UI elements only — **no visual style** (no colors, fonts, spacing).

> Keep this file current: whenever a screen's layout or element structure changes, update the matching section here. See CLAUDE.md.

## Navigation shell

`AppShell` — `NavigationBar` (bottom) with 5 tabs: **Dashboard · Expenses · Budgets · Analytics · Settings**. The Settings tab holds the data catalog (categories, tags, …). Expenses tab is behind a feature flag. Horizontal drag on the nav bar switches tabs. Body cross-fade/slide transition on tab change. Root route intercepts system back: requires a second back press within 2s to exit (toast on first press).

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

---

## Screens

### Dashboard (`dashboard_screen.dart`)
- **Header**: `AppTopBar` in month mode (month pager left, settings gear right). Selection mode (long-press a transaction): "N selected", X (clear), trash (delete-confirm).
- **FAB**: "+" → ExpenseEntryScreen (new).
- **Body** Column, top→bottom:
  1. `AppTopBar` — month/year chevron nav + settings gear (shared across months).
  2. **Balance hero** (`_BalanceHeader`, shared, sits *outside* the PageView): "Total Balance" label + large balance amount, then a Row of 2 collapsing stat tiles (Income · Spent; each = icon chip in a row beside a label + amount column). **Collapses on inner scroll**: balance shrinks, stat tiles fold away, a hairline bottom border fades in.
  3. Expanded horizontal `PageView` of month pages (swipe = month ±1, kept in sync with `MonthHeaderBar`). Each month page is a scrolling `ListView` driving the hero collapse, top→bottom:
     - If active budgets: "Active budgets" header + budget tiles (name, `ThinProgressBar`, spent/limit).
     - Transactions **grouped by day**: per-day header (uppercase day label + signed day total) followed by transaction rows (optional selection Checkbox, uppercase category line, title, method subtitle, signed amount). "No transactions" text when empty. Tap = edit / toggle; long-press = select.

### Expenses (`expenses_screen.dart`)
- **Header**: `AppTopBar` title "Expenses", trailing filter action (tinted when active) → `ExpenseFilterSheet` + settings gear. Selection mode: "N selected", X, trash.
- **FAB**: "+" → ExpenseEntryScreen (new).
- **Body**: paginated `ListView` of expense card tiles (optional Checkbox, title, date subtitle, signed amount). Trailing "Load more" TextButton when more pages. Empty/loading centered. Tap = edit/toggle; long-press = select.

### Budgets (`budgets_screen.dart`)
- **Header**: `AppTopBar` title "Budgets" + settings gear. Selection mode: "N selected", X, trash.
- **Search row** (hidden in selection mode): search pill (filter by name) + trailing archive toggle (active vs expired budgets).
- **FAB**: "+" → BudgetEntryScreen (new).
- **Body**: `ListView` of `AppCard` tiles (optional Checkbox, name, subtitle = `ThinProgressBar` + spent/limit). Empty/loading centered. Tap = edit/toggle; long-press = select.

### Analytics (`analytics_screen.dart`)
- **Header**: `AppTopBar` in month mode (month pager left, settings gear right).
- **Body** Column: `AppTopBar` + Expanded month `PageView`.
- **FAB**: icon-only `FloatingActionButton` toggles dimension; icon shows the *current* dimension — pie (category) / tag.
- **Each page** (ListView):
  1. `AppCard.large` panel: centered "Total spent" label + large centered amount; then (when data) optional breadcrumb Row (circular back + path, category view only) and a 240px donut `PieChart` (tap slice to drill in category view).
  2. Below the panel: legend rows (dot, label, amount, optional drill chevron). Tag view adds a disclaimer line. Empty state text when no data.

### Settings (`settings_screen.dart`)
Data catalog tab.
- **Header**: `AppTopBar` title "Settings" + gear (→ Account hub).
- **Body**: single `AppCard` Column of `HairlineListTile` nav rows: Categories, Tags, Tag groups, Payment methods, Events, Projects.

### Account (`account_screen.dart`)
Personal/app settings hub, pushed over the shell from the header gear.
- **AppBar**: empty (back button).
- **Body**: `PageTitleHeader` "Settings" + single `AppCard` Column of `HairlineListTile` rows: Profile, Export, Backup.

### Expense entry (`expense_entry/expense_entry_screen.dart`)
Full-screen entry.
- **AppBar**: leading back; title = `SegmentedButton` (Expense / Income / Refund).
- **Body** Column:
  1. Expanded fields ListView: Row [Date | Amount] · divider · Category · Payment method · Tags (count) · divider · Row [Event | Project] · divider · Description field · multiline Notes field.
  2. When panel open: inline action Row above panel — full-width "Save", or "Save"+"Next" in tags step.
  3. `BottomActionPanel`: `NumericKeypad` (amount), `_DatePanel` calendar (month nav + 7-col day grid), `CategoryPickerContent`, `SimplePickerContent`, or `TagPickerContent`.
  4. No panel: bottom SafeArea full-width "Save" button.
- Tapping a field row opens its panel; pickers auto-advance to next step (skip empty ref types). Pops `true` on save.

### Budget entry (`budget_entry/budget_entry_screen.dart`)
Full-screen entry; closes via X.
- **AppBar**: leading X.
- **Body** Column:
  1. Expanded ListView: Name field · "Limit" ListTile (euro icon, amount) → keypad · "Dimension" `SegmentedButton` (Category/Tag/Project/Event, disabled in edit) · "Select value" ListTile → picker (disabled in edit) · "Budget type" `SegmentedButton` (Range/Months/Total, disabled in edit) · conditional section:
     - **Range**: Start month + End month ListTiles (clear-X on end).
     - **Months**: Wrap of month Chips + "Add month" ActionChip.
     - **Total**: hint text.
  2. Inline "Save" above panel when open.
  3. `BottomActionPanel`: `NumericKeypad`, `MonthPickerContent`, `CategoryPickerContent`, or `SimplePickerContent`.
  4. No panel: bottom SafeArea full-width "Save" button.
- Pops `true` on save.

### Account › Backup (`settings/backup_screen.dart`)
- **AppBar**: empty.
- **Body**: `AppCard` Column of 2 `HairlineListTile`: "Export backup" (spinner trailing while busy) + "Restore backup". Export → share sheet; Restore → file picker + destructive confirm + toast.

### Account › Export (`settings/export_screen.dart`)
- **AppBar**: empty.
- **Body** ListView: From | To date TextButtons Row · "Type" dropdown (All/Expense/Income/Refund) · "Export CSV" button · "Export PDF" button · `LinearProgressIndicator` while busy. Both exports build rows → share sheet.

### Account › Profile (`settings/profile_screen.dart`)
- **AppBar**: empty.
- **Body** ListView: `PageTitleHeader` "Profile", then three labeled sections, each a section label above an `AppCard`: **Language** — one option row per locale (native name + trailing check on the selected one); **Theme** — three option rows (Light / Dark / System, trailing check on the selected one); **Currency** — single read-only `HairlineListTile` (coins icon) with the currency code as trailing text.

### Settings › Events (`settings/events_screen.dart`)
- **AppBar**: empty.
- **Body** Column: `PageTitleHeader` "Events" + Expanded `ListView` of `EntityListTile` (title = name, subtitle = description).
- **FAB**: "+" → `showEventProjectFormDialog` (new). Swipe edit/delete (delete confirm warns of dependent budgets).

### Settings › Projects (`settings/projects_screen.dart`)
Identical to Events with "Projects" title.

### Settings › Categories (`settings/categories_screen.dart`)
- **AppBar**: empty.
- **Body** Column: header = `PageTitleHeader` "Categories" at root, or breadcrumb Row (circular back + path) when drilled · Expanded `ReorderableListView` of `EntityListTile` (long-press drag reorder; tap descends into children; swipe edit/delete).
- **FAB**: "+" → `showEntityFormDialog`, hidden at depth ≥ 3 (max 3 levels).

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
- Selection mode (multi-delete) on Dashboard, Expenses, Budgets swaps `AppTopBar` contents (count + clear + delete).
- Entry screens (expense/budget) use the in-screen `BottomActionPanel` + `NumericKeypad` + embedded pickers, not modal sheets. The Expenses list uses a true modal filter sheet.

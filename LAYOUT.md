# Layout & Screens

Structural reference for every screen: layout and UI elements only — **no visual style** (no colors, fonts, spacing).

> Keep this file current: whenever a screen's layout or element structure changes, update the matching section here. See CLAUDE.md.

## Navigation shell

`AppShell` — `NavigationBar` (bottom) with 5 tabs: **Dashboard · Expenses · Budgets · Analytics · Settings**. Expenses tab is behind a feature flag. Horizontal drag on the nav bar switches tabs. Body cross-fade/slide transition on tab change. Root route intercepts system back: requires a second back press within 2s to exit (toast on first press).

---

## Shared widgets (referenced by role)

| Widget | Layout it provides |
| --- | --- |
| `PageTitleHeader` | Large in-body title Row: title left, optional trailing action right. Used where AppBar is title-less. |
| `MonthHeaderBar` | Centered Row: left chevron · month/year label · right chevron. Emits month ±1. |
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
- **AppBar**: title-less. Selection mode (long-press a transaction): centered "N selected", leading X (clear), trailing trash (delete-confirm).
- **FAB**: "+" → ExpenseEntryScreen (new).
- **Body** Column, top→bottom:
  1. `MonthHeaderBar` — month/year chevron nav (shared across months).
  2. **Balance hero** (`_BalanceHeader`, shared, sits *outside* the PageView): "Total Balance" label + large balance amount, then a Row of 2 collapsing stat tiles (Income · Spent, icon chip + label + amount). **Collapses on inner scroll**: balance shrinks, stat tiles fold away, a hairline bottom border fades in.
  3. Expanded horizontal `PageView` of month pages (swipe = month ±1, kept in sync with `MonthHeaderBar`). Each month page is a scrolling `ListView` driving the hero collapse, top→bottom:
     - If active budgets: "Active budgets" header + budget tiles (name, `ThinProgressBar`, spent/limit).
     - Transactions **grouped by day**: per-day header (uppercase day label + signed day total) followed by transaction rows (optional selection Checkbox, uppercase category line, title, method subtitle, signed amount). "No transactions" text when empty. Tap = edit / toggle; long-press = select.

### Expenses (`expenses_screen.dart`)
- **AppBar**: title-less, trailing filter IconButton (tinted when active) → `ExpenseFilterSheet`. Selection mode: "N selected", X, trash.
- **FAB**: "+" → ExpenseEntryScreen (new).
- **Body**: paginated `ListView` of expense card tiles (optional Checkbox, title, date subtitle, signed amount). Trailing "Load more" TextButton when more pages. Empty/loading centered. Tap = edit/toggle; long-press = select.

### Budgets (`budgets_screen.dart`)
- **AppBar**: title-less, trailing eye/eye-off toggle (active vs expired). Selection mode: "N selected", X, trash.
- **FAB**: "+" → BudgetEntryScreen (new).
- **Body**: `ListView` of `AppCard` tiles (optional Checkbox, name, subtitle = `ThinProgressBar` + spent/limit). Empty/loading centered. Tap = edit/toggle; long-press = select.

### Analytics (`analytics_screen.dart`)
- **AppBar**: empty.
- **Body** Column: `MonthHeaderBar` + `SegmentedButton` (By Category / By Tag) + Expanded month `PageView`.
- **Each page** (ListView):
  1. "Total spent" centered header + large centered amount.
  2. `AppCard`:
     - **Category view**: optional breadcrumb Row (back + path); 240px donut `PieChart` (center label, tap slice to drill); legend rows (dot, label, amount, optional drill chevron).
     - **Tag view**: 240px `PieChart`, disclaimer line, legend rows (no drill).

### Settings (`settings_screen.dart`)
- **AppBar**: empty.
- **Body**: single `AppCard` Column of `HairlineListTile` nav rows: Categories, Tags, Tag groups, Payment methods, Events, Projects, Profile, Export, Backup.

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

### Settings › Backup (`settings/backup_screen.dart`)
- **AppBar**: empty.
- **Body**: `AppCard` Column of 2 `HairlineListTile`: "Export backup" (spinner trailing while busy) + "Restore backup". Export → share sheet; Restore → file picker + destructive confirm + toast.

### Settings › Export (`settings/export_screen.dart`)
- **AppBar**: empty.
- **Body** ListView: From | To date TextButtons Row · "Type" dropdown (All/Expense/Income/Refund) · "Export CSV" button · "Export PDF" button · `LinearProgressIndicator` while busy. Both exports build rows → share sheet.

### Settings › Profile (`settings/profile_screen.dart`)
- **AppBar**: empty.
- **Body** ListView: `PageTitleHeader` "Profile" · "Language" label + one `RadioListTile` per locale · divider · `SwitchListTile` "Dark theme" · divider · read-only "Currency" ListTile.

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
- Top-level list screens (Dashboard, Expenses, Budgets, entry screens) use a real Material `AppBar` + `FloatingActionButton`. All `settings/*` list screens leave the AppBar empty and render their title via `PageTitleHeader`.
- Selection mode (multi-delete) on Dashboard, Expenses, Budgets swaps AppBar contents.
- Entry screens (expense/budget) use the in-screen `BottomActionPanel` + `NumericKeypad` + embedded pickers, not modal sheets. The Expenses list uses a true modal filter sheet.

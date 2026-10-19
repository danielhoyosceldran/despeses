# Layout & Screens

Structural reference for every screen: layout and UI elements only — **no visual style** (no colors, fonts, spacing).

> Keep this file current: whenever a screen's layout or element structure changes, update the matching section here. See CLAUDE.md.

## Navigation shell

`AppShell` — `NavigationBar` (bottom) with 5 tabs: **Dashboard · Transactions · Budgets · Analytics · Settings**. The Settings tab holds the data catalog (categories, tags, …). Horizontal drag on the nav bar switches tabs. Tab change is instant (the shell's IndexedStack); no body transition — animating the shell itself duplicates its GlobalKey. Root route intercepts system back: requires a second back press within 2s to exit (toast on first press).

The header gear (`AppTopBar`) opens a separate **Account** hub (Profile · Export · Backup) pushed over the shell — distinct from the Settings tab.

---

## Shared widgets (referenced by role)

| Widget | Layout it provides |
| --- | --- |
| `PageTitleHeader` | Large in-body title Row: title left, optional trailing action right. Used where AppBar is title-less. |
| `AppTopBar` | Shared in-body top header (no Material AppBar). Left: month pager (chevron · uppercase month/year · chevron, emits month ±1) **or** a display title. When given the page's `PageController`, the month label tracks the swipe continuously (sliding filmstrip revealing the incoming month) instead of flipping on settle. Trailing: optional actions (`TopBarCircleButton`s) then a settings gear that pushes the Account hub. In selection mode swaps to: leading X (clear) · "N selected" · trailing trash (delete). Settings gear hideable. |
| `TopBarCircleButton` | Circular header action (ghost or filled chip); used for chevrons, gear, and per-screen actions (filter, active/expired eye). |
| `BottomActionPanel` | In-screen animated bottom panel (not modal). Height 0→content, rounded top. Hosts pickers. |
| `AmountInputField` | Centered amount hero as an editable text field using the device's numeric keyboard, with the currency symbol after it. Keyboard action key = "Next". Used as the amount hero on the expense/budget/goal/recurring entry screens. |
| `ExpenseFilterSheet` | Modal sheet. "Filters" title; scrolling body of collapsible multi-select sections (title + summary of the selection, or "Any"): Type (chips: expense, income, refund, savings), Category, Tags, Payment method, Event and Project (chips; Event/Project only when any exist); then a Min/Max amount Row and a From/To date Row. Pinned "Clear"/"Apply" Row. Within a section any selected value matches; sections combine. The Category section is a checkbox tree grouped by transaction type: an uppercase type header, then each root category followed by its subcategories, indented by depth; checking a parent filters its whole subtree. An inverted From/To or Min/Max range is swapped on Apply with a warning toast. |
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
- **Header**: `AppTopBar` in month mode (month pager left; trailing: refresh · settings gear). Selection mode (long-press a transaction): "N selected", X (clear), trash (delete-confirm).
- **FAB**: "+" → ExpenseEntryScreen (new). Tap, or drag up to interactively pull the entry screen up from the bottom (finger is the animation motor).
- **Body** Column, top→bottom:
  1. `AppTopBar` — month/year chevron nav + settings gear (shared across months).
  2. **Balance hero** (`_BalanceHeader`, shared, sits *outside* the PageView): "Total Balance" label + large balance amount, then a Row of 3 collapsing stat tiles (Income · Spent · Savings; each = a row of icon chip + label, with the amount below). Spent excludes savings; the balance is income − spent − savings. **Collapses on inner scroll**: balance shrinks, stat tiles fold away, a hairline bottom border fades in.
  3. Expanded horizontal `PageView` of month pages (swipe = month ±1, kept in sync with `MonthHeaderBar`). Each month page is a scrolling `ListView` driving the hero collapse, top→bottom:
     - If active budgets: "Active budgets" header + a fixed 2-column budget grid (`_BudgetGrid`, capped at 4). 1–2 budgets = one row; 3–4 = 2×2, trailing gap filled with an empty slot. Each tile: row 1 = name + percent spent, row 2 = `ThinProgressBar`; tapping any tile switches to the Budgets tab.
     - **Recurring-due section** (`_RecurringDueSection`, directly below the active-budgets block; shown only when recurring occurrences are pending and not in selection mode). Header row: "Recurring due" title (head) + a "Review" + chevron tail link → `/settings/recurring`. Below it a fixed 2-column grid (`_RecurringDueGrid`, capped at 4) following the budget-grid rules: 1–2 items = one row, 3–4 = 2×2, trailing gap filled with an empty slot. Each tile (`_RecurringDueTile`) has two cross-fading faces: **default** = one row with name (left) + signed amount (right); **armed** (after a tap) = a split reject (✕, left) / accept (✓, right) control that auto-reverts after 3s. Tapping another tile reverts the previous. Reject → `skip`; accept → `confirm` (registers the real transaction); the confirmed/rejected tile leaves the grid and the next pending item (5th onward) takes its place.
     - Transactions **grouped by day**: per-day header (uppercase day label + signed day total) followed by transaction rows (optional selection Checkbox, uppercase category line, title, a muted "Scheduled" line for future-dated rows, method subtitle, signed amount). Future-dated rows are listed but left out of the hero totals until their day. "No transactions" text when empty. Tap = edit / toggle; long-press = select.
     - On load failure the page body shows `ErrorRetry` instead of the transaction list.

### Transactions (`expenses_screen.dart`)
- **Header**: `AppTopBar` title "Transactions", trailing filter action (tinted when any filter other than the "This month" range is active) → `ExpenseFilterSheet` + settings gear. Selection mode: "N selected", X, trash.
- **Search row** (fixed, hidden in selection mode): search pill (leading search icon, hint with the query syntax, trailing clear button when non-empty) + trailing "This month" chip. The screen opens with the chip on (date range = current month); tapping it clears the date range, tapping again restores the current month. Picking another range in the filter sheet turns it off. Query syntax (`TransactionQuery`, `domain/search/transaction_search.dart`): space-separated terms, all must match; plain text matches title or notes (case/accent-insensitive); `>`, `<`, `>=`, `<=`, `=`, `!=` + number compare the amount; a bare number matches the exact amount or the text. The search applies on top of the filters.
- **FAB**: "+" → ExpenseEntryScreen (new). Tap, or drag up to interactively pull the entry screen up from the bottom (finger is the animation motor).
- **Body**: live, lazily built list: results header ("N results" + signed net) then transactions **grouped by day** like the Dashboard (per-day header with uppercase day label — with the year for days of another year — and signed day total, then shared `ExpenseRow`s). Empty state: "No matching transactions" when searching/filtering, otherwise "No transactions". Loading centered; `ErrorRetry` on failure. Tap = edit/toggle; long-press = select.

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
- **Header**: `AppTopBar` — month mode (month pager) only on month-scoped sections; on the non-month section (Events) it shows the section title instead of the pager. Settings gear always right.
- **Section FAB**: circular FAB showing the current section's own icon (no label). Tap opens a bottom-sheet menu listing every section, each with its icon (current highlighted with a check). Drag gestures: a **vertical** drag steps sections one at a time (up = next, down = previous); a **horizontal-left** drag toggles between the two **preferred** sections (Categories ↔ Tags). Neither collides with the body's horizontal month swipe (that lives in the PageView). While a drag is armed, a **centred floating preview card** (`_SectionPreviewCard`: target section's icon + name) appears mid-screen over the body. Section order: Categories · Tags · Budgets · Events.
- **Body**: a `PageView` — month-scoped sections are swipeable left/right to change month (tracked by the header label + chevrons, mirroring Dashboard); the non-month section (Events) disables the swipe. Each section is a scrolling `ListView` of `StatCard`s / panels. Each section has three states: loading spinner, `ErrorRetry` on failure, or its data body.
- **Sections**:
  - **Categories / Tags** (preferred): `AppCard.large` donut (`DonutChart`) with the total in the hole (Categories also shows the transaction count under it), then a `BreakdownCard` listing every slice as a `BreakdownRow` (dot, name, amount, proportional bar, transaction count, % of total, chevron), sorted largest first. Leaf-only, so no "direct" slice. Tapping any slice or row opens its detail screen (below). Tags: the donut and row amounts are spending only; a tag that also has savings adds "Savings: X" to its row's meta line (tags with only savings are not listed); italic disclaimer below the card.
- **Detail screens** (`analytics/analytics_detail.dart`, pushed as real `CupertinoPageRoute`s so the OS back gesture pops one level). Shared structure: `AppTopBar` titled with the item → `DetailBreadcrumb` (circular back + path + month) → `DetailSummaryCard` (Spent label, big total, "N transactions · avg X", savings line when present) → optional breakdown → "Transactions" header with count → `TransactionsByDay` (per-day uppercase date headers + shared `ExpenseRow`s; tap opens the transaction in the entry screen, and saving refreshes analytics).
  - **Category detail** (`CategoryDetailScreen`, any depth): breakdown = "Subcategories" header + subcategory donut (count of subcategories in the hole) + `BreakdownCard`, only when it has subcategories with spend; tapping one pushes another category detail. Transactions = the whole subtree's expenses of the month.
  - **Tag detail** (`TagDetailScreen`): breadcrumb `#tag`; breakdown = "By category" `BreakdownCard` (expense-type spend per category, uncategorized grouped apart; rows not tappable). Transactions = every transaction carrying the tag that month.
  - **Budgets**: per active budget, progress bar + pace/projection line.
  - **Events**: event dropdown selector + total/€-per-day tiles (total excludes savings) + a full-width "Savings" tile below them only when the event has savings + spend timeline + out-of-range notice + "Transactions" header with `TransactionsByDay` list of all the event's transactions.
- **Shared chart widgets** live in `widgets/charts/` (`donut_chart.dart`: `DonutChart`, `BreakdownRow`, `BreakdownCard`; `analytics_widgets.dart`: `KpiTile`, `TrendLines`, `StatCard`, `StatInfoButton`).
- **Info button**: most `StatCard`s, `KpiTile`s and the Category/Tags donut cards carry a small "i" (`StatInfoButton`) beside their title. Tap opens a bottom sheet (`showStatInfoSheet`, drag handle, `isScrollControlled`) with a plain-language explanation of the stat and an optional example widget.

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
  1. Expanded fields ListView: centered type selector (Expense · Income · Refund · Savings as tappable text separated by "|"; selected takes its colour + bold, clears category on change) · big centered amount (`AmountInputField`, system numeric keyboard) · Description field (themed filled input, no wrapping card) · `AppCard` of rows [Category · Payment method · Tags (count) · Row [Event | Project]] · multiline Notes field (themed filled input, no wrapping card).
  2. When panel open: inline action Row above panel — full-width "Save", or "Save"+"Next" in tags step.
  3. `BottomActionPanel`: `CalendarPanel` (shared month nav + 7-col day grid), `CategoryPickerContent`, `SimplePickerContent`, or `TagPickerContent`.
  4. No panel: bottom SafeArea full-width "Save" button.
- A blank new transaction starts with the favorite payment method preselected (not when editing or when seeded from a recurring).
- Tapping a field row opens its panel. "Next" auto-advances through amount → description → category → payment method (skipped when one is already picked), then stops; remaining fields (tags, event, project, notes) are filled manually. Skips empty ref types. Pops `true` on save.
- Can be opened pre-filled from a `ExpenseSeed` (recurring "edit & confirm" flow): all fields hydrated, amount field is not auto-focused.

### Budget entry (`budget_entry/budget_entry_screen.dart`)
Full-screen entry; opens by sliding up from the bottom, dismisses sliding down.
- **AppBar**: leading down-chevron (dismiss); title ("New budget" / "Edit budget").
- **Body** Column:
  1. Expanded ListView:
     - **Limit hero**: centered uppercase "LIMIT" header + centered `AmountInputField` (system numeric keyboard).
     - **Name** field (themed filled input, no wrapping card).
     - **Tracks** section (uppercase header) — 2×2 grid of toggle cells (Category/Tag/Project/Event, disabled in edit) + `AppCard` value row → picker (disabled in edit).
     - **Period** section (uppercase header):
       - **Category/Tag** dimension — `SegmentedButton` (Monthly/Range, disabled in edit) + conditional:
         - **Monthly**: hint text (recurs every month).
         - **Range**: `AppCard` with From + Until field rows (both required, divider between).
       - **Project/Event** dimension — no picker; period is fixed to the entity's own duration. Read-only `AppCard` (From/Until months) + caption when the entity has dates, else a warning that the event/project needs start/end dates.
  2. Inline "Save" above panel when open.
  3. `BottomActionPanel`: `MonthPickerContent`, `CategoryPickerContent`, or `SimplePickerContent`.
  4. No panel: bottom SafeArea full-width "Save" button.
- New budget: amount field is focused first; the keyboard's "Next" auto-advances amount → name, then stops (dimension, value, period chosen manually). Pops `true` on save.

### Goal entry (`goal_entry/goal_entry_screen.dart`)
Full-screen entry; opens by sliding up from the bottom, dismisses sliding down. Creates/edits a savings goal.
- **AppBar**: leading down-chevron (dismiss); title ("New goal" / "Edit goal").
- **Body** Column:
  1. Expanded ListView:
     - **Target hero**: centered uppercase "TARGET" header + centered `AmountInputField` (system numeric keyboard).
     - **Name** field.
     - **Savings category** section (uppercase header) — `AppCard` value row → `ahorro`-scoped category picker (locked in edit).
     - **Deadline** section (uppercase header) — `AppCard` row → calendar panel; shows "No deadline" placeholder with a trailing clear button when set.
  2. Inline "Save" above panel when open.
  3. `BottomActionPanel`: `CategoryPickerContent` (ahorro tree), or `CalendarPanel` (deadline).
  4. No panel: bottom SafeArea full-width "Save" button.
- New goal: amount field is focused first; the keyboard's "Next" moves amount → name. Category + currency lock after creation; only name/target/deadline stay editable. Pops `true` on save.

### Recurring entry (`recurring/recurring_entry_screen.dart`)
Full-screen entry; opens by sliding up from the bottom, dismisses sliding down. Creates/edits a recurring-transaction template. Every field editable in both new and edit modes.
- **AppBar**: leading down-chevron (dismiss); centered title ("New recurring" / "Edit recurring").
- **Body** Column:
  1. Expanded ListView: centered type selector (Expense · Income · Refund · Savings) · big centered amount (`AmountInputField`, system numeric keyboard) · Description field · **Schedule** section (uppercase header): `SegmentedButton` (Monthly/Weekly/Yearly) + `AppCard` with Starts row and Ends row (Ends shows "No end date" placeholder with a trailing clear button when set) · **Details** section (uppercase header): `AppCard` of rows [Category · Payment method · Tags (count) · Row [Event | Project]] · multiline Notes field.
  2. Inline "Save" above panel when open ("Save"+"Next" in tags step).
  3. `BottomActionPanel`: `CalendarPanel` (start/end date), `CategoryPickerContent`, `SimplePickerContent`, or `TagPickerContent`.
  4. No panel: bottom SafeArea full-width "Save" button.
- New: amount field is focused first; the keyboard's "Next" moves amount → description. Save requires amount > 0 + non-empty description + end date not before start. Pops `true` on save (then materializes any already-due dates).

### Settings › Recurring (`recurring/recurring_screen.dart`)
- **Header**: `AppTopBar` title "Recurring". Selection mode (long-press a template): "N selected", X (clear), trash (delete-confirm).
- **FAB**: "+" → RecurringEntryScreen (new). Tap, or drag up to interactively pull it up from the bottom.
- **Body** `ListView`, two stacked sections:
  - **Pending** (only when occurrences await confirmation): uppercase "PENDING" header with a "Confirm all" TextButton when >1, then one `_PendingCard` per occurrence — description + due date + amount, with Skip / Edit / Confirm actions. Confirm → creates the real transaction; Edit → opens the seeded `ExpenseEntryScreen` (saving there confirms the occurrence); Skip → discards. Actions show a toast; a card's actions (and "Confirm all") are disabled while one is in progress. "Confirm all" is all-or-nothing and shows an error toast on failure.
  - **Templates**: uppercase "TEMPLATES" header, then one `_TemplateCard` per template (name, subtitle = frequency + next date, "Paused", or "Finished" once past its end date; trailing amount + active `Switch` — for a finished template the switch is replaced by a "Reactivate" TextButton that opens the editor to extend the end date). Tap = edit; long-press = select. `EmptyState` when none.

### Account › Backup (`settings/backup_screen.dart`)
- **AppBar**: empty.
- **Body**: `AppCard` Column of `HairlineListTile`: "Export backup" (spinner trailing while busy) + "Restore backup", plus "Undo restore" (subtitle with the date of the saved copy) only when a pre-restore copy exists. Export → share sheet; Restore → file picker + destructive confirm + toast (the current data is saved first); Undo restore → destructive confirm, then restores the data from before the last restore.

### Account › Export (`settings/export_screen.dart`)
- **AppBar**: empty.
- **Body** ListView: From | To date TextButtons Row · "Type" dropdown (All/Expense/Income/Refund) · "Export CSV" button · "Export PDF" button · `LinearProgressIndicator` while busy. Both exports build rows → share sheet.

### Account › Profile (`settings/profile_screen.dart`)
- **AppBar**: empty.
- **Body** ListView: `PageTitleHeader` "Profile", then three labeled sections, each a section label above an `AppCard`: **Language** — one option row per locale (native name + trailing check on the selected one); **Theme** — three option rows (Light / Dark / System, trailing check on the selected one); **Currency** — single read-only `HairlineListTile` (coins icon) with the currency code as trailing text; **Feedback** — a single toggle row (label + trailing `Switch`) for Haptics.

### Settings CRUD lists — shared `EntityListTile` selection mode
Applies to Events, Projects, Categories, Tag groups, Payment methods, Tags.
Each list has three states: loading spinner, `EmptyState` (shared widget) when
the list is empty, or the item list. Categories/Tags show `EmptyState` at the
current level/group (not just when the whole catalog is empty).
Two row modes:
- **Normal**: leading avatar (icon/initial); tap = act (open/descend, or nothing
  for leaf lists); long-press = enter selection mode with this row checked.
  Trailing: a star on the favorite row (Payment methods only), then a chevron
  when the row opens/descends.
- **Selection mode** (entered via any row's long-press): leading swaps to a
  `Checkbox`; trailing shows an edit pencil icon (`onEdit`) and, on
  reorderable lists, a drag-handle icon (`ReorderableDragStartListener`,
  replaces the old whole-row long-press-to-drag); tap toggles the checkbox.
  AppBar shows a trailing trash icon (bulk delete selected, confirms once)
  and a "Done" text button (exits selection mode, clears selection).

### Settings › Events (`settings/events_screen.dart`)
- **AppBar**: empty normally; selection-mode actions (trash, Done) per above.
- **Body** Column: `PageTitleHeader` "Events" + Expanded `ListView` of `EntityListTile` (title = name, subtitle = description).
- **FAB**: "+" → `showEventProjectFormDialog` (new).

### Settings › Projects (`settings/projects_screen.dart`)
Identical to Events with "Projects" title.

### Settings › Categories (`settings/categories_screen.dart`)
- **AppBar**: empty normally; selection-mode actions (trash, Done) per above.
- **Body** Column: at root, `PageTitleHeader` "Categories" + a full-width `SegmentedButton` (Expense / Income / Refund / Savings) that switches which per-type category tree is shown; when drilled, a breadcrumb Row (circular back + path) replaces both · Expanded `ReorderableListView` of `EntityListTile` (tap descends into children outside selection mode; drag handle reorders inside selection mode).
- **FAB**: "+" → `showEntityFormDialog`, hidden at depth ≥ 3 (max 3 levels). New categories are created in the currently selected type's tree.

### Settings › Tag groups (`settings/tag_groups_screen.dart`)
- **AppBar**: empty normally; selection-mode actions (trash, Done) per above.
- **Body** Column: `PageTitleHeader` "Tag groups" + Expanded `ReorderableListView` of `EntityListTile`. "Ungrouped" group can't enter selection (no long-press/checkbox) and has edit disabled.
- **FAB**: "+" → `showEntityFormDialog` (name only). Delete moves tags to Ungrouped.

### Settings › Payment methods (`settings/payment_methods_screen.dart`)
Same as Tag groups: `PageTitleHeader` "Payment methods" + reorderable `EntityListTile` list (icon, no color; the favorite row shows a trailing star). FAB "+" → `showEntityFormDialog` (with icon and a "Favorite" toggle row; the edit dialog has the same toggle). At most one favorite: turning it on for one method moves it there; deleting the favorite clears it. Deleting every remaining method is refused with a warning toast (at least one must stay).

### Settings › Tags (`settings/tags_screen.dart`)
- **AppBar**: empty normally; selection-mode actions (trash, Done) per above.
- **Body** Column: `PageTitleHeader` "Tags" + Expanded outer `ListView` (or `EmptyState` if there are no groups at all), one section per tag group. Each section: group header Row (name + trailing "+" to add tag to group) above either an `EmptyState` (group has no tags) or a nested non-scrolling `ReorderableListView` of `EntityListTile` (reorder handle in selection mode). Selection spans across groups. No FAB.

---

## Cross-screen patterns
- Tab screens (Dashboard, Transactions, Budgets, Analytics, Settings) have no Material `AppBar`; they render a shared in-body `AppTopBar` (month pager or title + settings gear) and, where they create, a `FloatingActionButton`. Entry screens still use a real Material `AppBar`. All `settings/*` list screens leave the AppBar empty and render their title via `PageTitleHeader`.
- Selection mode (multi-delete) on Dashboard, Transactions, Budgets (both tabs), Recurring swaps `AppTopBar` contents (count + clear + delete).
- Entry screens (expense/budget/goal/recurring) use the in-screen `BottomActionPanel` + embedded pickers (amount via `AmountInputField` + system keyboard), not modal sheets. The Transactions list uses a true modal filter sheet.
- Entry screens closing with unsaved changes (any field differing from its loaded/initial value) via the down-chevron, swipe down, or system back show a destructive "Discard changes?" confirm dialog (Cancel / Discard) first; without changes they close directly. A failed save shows an error toast and keeps the screen open.
- Recurring (reached from the Settings hub, but not a `settings/*` list screen) renders an `AppTopBar` + FAB like a tab screen, rather than the `PageTitleHeader` used by the catalog list screens.

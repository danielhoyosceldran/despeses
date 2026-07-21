import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format/money.dart';
import '../../core/haptics/haptics.dart';
import '../../core/i18n/display_name.dart';
import '../../core/navigation/bottom_up_route.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/expense_repository.dart';
import '../widgets/amount_text.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/drag_up_fab.dart';
import '../widgets/entity_form_dialog.dart' show chartPalette;
import '../widgets/error_retry.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/thin_progress_bar.dart';
import 'expense_entry/expense_entry_screen.dart';

/// Month-scoped overview. Hybrid dashboard: a shared collapsing balance hero
/// (balance + Income/Spent tiles) sits above a swipeable month [PageView] whose
/// pages list the month's transactions grouped by day. The active page's inner
/// scroll drives the hero collapse.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

/// Large enough that the user can't scroll past either edge in a session;
/// each page index maps to a calendar month offset from [_baseMonth].
const int _kInitialPage = 6000;

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late final DateTime _baseMonth;
  late final PageController _pageController;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  List<Budget> _allBudgets = [];
  Map<String, int> _budgetProgress = {};
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _toggleSelection(Expense expense) {
    setState(() {
      if (_selectedIds.contains(expense.id)) {
        _selectedIds.remove(expense.id);
      } else {
        _selectedIds.add(expense.id);
      }
    });
  }

  String _monthKeyOf(DateTime month) => '${month.year}-${month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _baseMonth = DateTime(_month.year, _month.month);
    _pageController = PageController(initialPage: _kInitialPage);
    _loadBudgets();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) => DateTime(_baseMonth.year, _baseMonth.month + (page - _kInitialPage));

  DateTime _monthBounds(DateTime month) => DateTime(month.year, month.month + 1, 0);

  Stream<List<Expense>> _watchMonth(DateTime month) {
    final repo = ref.read(expenseRepositoryProvider);
    return repo.watchAll(
      filters: ExpenseFilters(dateFrom: DateTime(month.year, month.month, 1), dateTo: _monthBounds(month)),
    );
  }

  Future<void> _loadBudgets() async {
    final budgetRepo = ref.read(budgetRepositoryProvider);
    final allBudgets = await budgetRepo.listAll();
    final progress = <String, int>{};
    for (final budget in allBudgets) {
      progress[budget.id] = await budgetRepo.calculateProgress(budget, inMonth: _month);
    }
    if (!mounted) return;
    setState(() {
      _allBudgets = allBudgets;
      _budgetProgress = progress;
    });
  }

  void _changeMonth(int delta) {
    final target = (_pageController.page ?? _kInitialPage.toDouble()).round() + delta;
    _pageController.animateToPage(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _onPageChanged(int page) {
    setState(() => _month = _monthForPage(page));
  }

  Future<void> _openEntry({String? expenseId}) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      bottomUpRoute(ExpenseEntryScreen(expenseId: expenseId)),
    );
    if (saved == true) {
      _loadBudgets();
    }
  }

  Future<void> _deleteSelected() async {
    final translations = ref.read(translationsProvider).asData?.value;
    final count = _selectedIds.length;
    final confirmed = await showConfirmDialog(
      context,
      title: translations?.t('dashboard.delete_title') ?? 'Delete transactions',
      message: (translations?.t('dashboard.delete_message') ?? 'Delete {{count}} selected transaction(s)?')
          .replaceAll('{{count}}', '$count'),
      destructive: true,
    );
    if (!confirmed) return;
    final repo = ref.read(expenseRepositoryProvider);
    for (final id in _selectedIds) {
      await repo.delete(id);
    }
    setState(() {
      _selectedIds.clear();
    });
    _loadBudgets();
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;
    final profileAsync = ref.watch(profileStreamProvider);
    final currency = profileAsync.asData?.value.currency ?? 'EUR';
    final colors = context.appColors;

    return Scaffold(
      floatingActionButton: DragUpAction(
        pageBuilder: (_, close) => ExpenseEntryScreen(onClose: close),
        onResult: (saved) {
          if (saved == true) {
            _loadBudgets();
          }
        },
        builder: (context, armed, onTap) => PressableScale(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
              boxShadow: AppShadows.fab(colors),
            ),
            child: Icon(LucideIcons.plus300, color: colors.onAccent, size: 24),
          ),
        ),
      ),
      body: Column(
        children: [
          AppTopBar(
            month: _month,
            onChangeMonth: _changeMonth,
            pageController: _pageController,
            monthForPage: _monthForPage,
            fallbackPage: _kInitialPage,
            selectionCount: _selectedIds.length,
            onClearSelection: () => setState(() => _selectedIds.clear()),
            onDeleteSelection: _deleteSelected,
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final month = _monthForPage(index);
                return _MonthPage(
                  key: ValueKey(_monthKeyOf(month)),
                  month: month,
                  watchExpenses: _watchMonth,
                  allBudgets: _allBudgets,
                  budgetProgress: _budgetProgress,
                  currency: currency,
                  translations: translations,
                  onOpenEntry: _openEntry,
                  selectionMode: _selectionMode,
                  selectedIds: _selectedIds,
                  onToggleSelection: _toggleSelection,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashboard mini-section (feature 3.13) surfacing recurring occurrences that
/// are due and awaiting the user's confirm/reject, as a 2-column grid capped at
/// 4 tiles. Header carries the section title (head) and a tail link that opens
/// the full Recurring screen. Tapping a tile arms it: the title/amount are
/// swapped for a reject (✕) / accept (✓) pair for 3s, then it auto-reverts.
/// Arming a different tile reverts the previous one. Accepting confirms the
/// occurrence into a real transaction; the stream then drops it and the next
/// pending item (5th onward) takes its place.
class _RecurringDueSection extends ConsumerStatefulWidget {
  const _RecurringDueSection({required this.translations});

  final Translations? translations;

  @override
  ConsumerState<_RecurringDueSection> createState() => _RecurringDueSectionState();
}

class _RecurringDueSectionState extends ConsumerState<_RecurringDueSection> {
  /// Occurrence id currently showing its accept/reject controls, or null.
  String? _armedId;
  Timer? _revertTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  void _arm(String id) {
    ref.read(hapticsProvider).selection();
    _revertTimer?.cancel();
    // Tapping the armed tile again folds it back.
    if (_armedId == id) {
      setState(() => _armedId = null);
      return;
    }
    setState(() => _armedId = id);
    _revertTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _armedId = null);
    });
  }

  Future<void> _accept(RecurringOccurrence occ) async {
    _revertTimer?.cancel();
    ref.read(hapticsProvider).medium();
    _armedId = null; // stream will rebuild without this tile
    await ref.read(recurringRepositoryProvider).confirm(occ);
  }

  Future<void> _reject(RecurringOccurrence occ) async {
    _revertTimer?.cancel();
    ref.read(hapticsProvider).light();
    _armedId = null;
    await ref.read(recurringRepositoryProvider).skip(occ.id);
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingRecurringProvider).asData?.value ?? const <RecurringOccurrence>[];
    if (pending.isEmpty) return const SizedBox.shrink();
    final colors = context.appColors;
    final t = widget.translations;
    final visible = pending.take(4).toList();
    // Drop a stale armed id once its tile is gone (accepted/rejected).
    if (_armedId != null && !visible.any((o) => o.id == _armedId)) {
      _armedId = null;
    }

    // Rendered inside the month page's already-padded content list, directly
    // below the active-budgets block, so no outer horizontal padding here.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.smMd),
          child: Row(
              children: [
                Expanded(
                  child: Text(
                    (t?.t('dashboard.recurring_due') ?? 'Recurring due').toUpperCase(),
                    style: appHeaderStyle(colors),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(AppDimens.radiusCard),
                  onTap: () => context.push('/settings/recurring'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t?.t('recurring.review') ?? 'Review',
                          style: TextStyle(color: colors.accent, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                        const SizedBox(width: 2),
                        Icon(LucideIcons.chevronRight300, size: 14, color: colors.accent),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        _RecurringDueGrid(
          occurrences: visible,
          armedId: _armedId,
          onArm: _arm,
          onAccept: _accept,
          onReject: _reject,
        ),
      ],
    );
  }
}

/// 2-column grid mirroring the budget grid rules: 1 row for ≤2 items, 2 rows
/// for 3–4, with a placeholder filling any trailing gap to keep alignment.
class _RecurringDueGrid extends StatelessWidget {
  const _RecurringDueGrid({
    required this.occurrences,
    required this.armedId,
    required this.onArm,
    required this.onAccept,
    required this.onReject,
  });

  final List<RecurringOccurrence> occurrences;
  final String? armedId;
  final void Function(String id) onArm;
  final void Function(RecurringOccurrence occ) onAccept;
  final void Function(RecurringOccurrence occ) onReject;

  @override
  Widget build(BuildContext context) {
    final rows = occurrences.length <= 2 ? 1 : 2;
    final cells = <RecurringOccurrence?>[...occurrences];
    while (cells.length < rows * 2) {
      cells.add(null);
    }

    Widget cell(RecurringOccurrence? occ) => Expanded(
          child: occ == null
              ? const _RecurringDuePlaceholder()
              : _RecurringDueTile(
                  occ: occ,
                  armed: occ.id == armedId,
                  onArm: () => onArm(occ.id),
                  onAccept: () => onAccept(occ),
                  onReject: () => onReject(occ),
                ),
        );

    return Column(
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cell(cells[r * 2]),
                const SizedBox(width: AppSpacing.sm),
                cell(cells[r * 2 + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Empty trailing slot keeping the grid aligned (mirrors `_BudgetPlaceholder`).
class _RecurringDuePlaceholder extends StatelessWidget {
  const _RecurringDuePlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        color: colors.surfaceAlt.withValues(alpha: 0.4),
      ),
    );
  }
}

/// A single due-occurrence tile. Default face: one row with the name on the
/// left and the signed amount on the right. Armed face: a split reject (✕) /
/// accept (✓) control. Cross-fades between the two.
class _RecurringDueTile extends StatelessWidget {
  const _RecurringDueTile({
    required this.occ,
    required this.armed,
    required this.onArm,
    required this.onAccept,
    required this.onReject,
  });

  final RecurringOccurrence occ;
  final bool armed;
  final VoidCallback onArm;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          border: Border.all(color: colors.borderSoft, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: armed ? _buildArmed(context) : _buildFace(context),
        ),
      ),
    );
  }

  Widget _buildFace(BuildContext context) {
    final colors = context.appColors;
    final sign = switch (occ.type) {
      'income' => '+',
      'refund' => '±',
      _ => '-',
    };
    final amountColor = context.amountColorForType(occ.type);
    final title = occ.description?.isNotEmpty == true ? occ.description! : occ.type;
    return InkWell(
      key: const ValueKey('face'),
      onTap: onArm,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.smMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$sign${formatMoney(occ.amount, occ.currency)}',
              style: appDisplay(colors, fontSize: 16, color: amountColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArmed(BuildContext context) {
    final colors = context.appColors;
    final semantic = context.semanticColors;
    Widget action({
      required IconData icon,
      required Color color,
      required VoidCallback onTap,
    }) =>
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Container(
              color: pillBackground(color),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 22),
            ),
          ),
        );
    return Row(
      key: const ValueKey('armed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        action(icon: LucideIcons.x300, color: semantic.expense, onTap: onReject),
        Container(width: 1, color: colors.borderSoft),
        action(icon: LucideIcons.check300, color: semantic.income, onTap: onAccept),
      ],
    );
  }
}

/// Signed monthly totals in the profile currency (accounting rule: expense
/// and ahorro subtract, refund adds back, income is tracked separately).
class _Totals {
  const _Totals({required this.spent, required this.income});
  final int spent;
  final int income;
  int get balance => income - spent;

  factory _Totals.of(List<Expense> expenses, String currency) {
    var spent = 0;
    var income = 0;
    for (final e in expenses) {
      if (e.currency != currency) continue;
      switch (e.type) {
        case 'expense':
        case 'ahorro':
          spent += e.amount;
        case 'refund':
          spent -= e.amount;
        case 'income':
          income += e.amount;
      }
    }
    return _Totals(spent: spent, income: income);
  }
}

/// Collapsing balance hero. [t] 0→1: balance shrinks 60→30, the Income/Spent
/// tiles fold away, and a hairline bottom border fades in.
class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.totals, required this.currency, required this.t, required this.translations});

  final _Totals totals;
  final String currency;
  final double t;
  final Translations? translations;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final semantic = context.semanticColors;
    return ClipRect(
      child: Container(
      width: double.infinity,
      alignment: Alignment.topCenter,
      color: colors.bg,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        lerpDouble(AppSpacing.md, AppSpacing.sm, t)!,
        AppSpacing.lg,
        lerpDouble(0, AppSpacing.smMd, t)!,
      ),
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider.withValues(alpha: t), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            translations?.t('dashboard.total_balance') ?? 'Total Balance',
            style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: lerpDouble(13, 12, t)),
          ),
          const SizedBox(height: AppSpacing.xs),
          AmountText(
            amountCents: totals.balance,
            currency: currency,
            style: appDisplay(colors, fontSize: lerpDouble(60, 30, t)!),
          ),
          // Income / Spent tiles collapse away as t → 1.
          ClipRect(
            child: Align(
              heightFactor: (1 - t).clamp(0.0, 1.0),
              child: Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: translations?.t('analytics.income') ?? 'Income',
                          value: totals.income,
                          currency: currency,
                          icon: LucideIcons.arrowDownRight,
                          color: semantic.income,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _StatTile(
                          label: translations?.t('analytics.spent') ?? 'Spent',
                          value: totals.spent,
                          currency: currency,
                          icon: LucideIcons.arrowUpRight,
                          color: semantic.expense,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Income/Spent stat tile: muted fill, hairline border, colored icon chip.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.currency,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final String currency;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.mutedFill(0.30),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: Border.all(color: colors.borderSoft, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: iconChipBackground(color), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: AppSpacing.xs),
                AmountText(
                  amountCents: value,
                  currency: currency,
                  style: appDisplay(colors, fontSize: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthPage extends ConsumerWidget {
  const _MonthPage({
    required super.key,
    required this.month,
    required this.watchExpenses,
    required this.allBudgets,
    required this.budgetProgress,
    required this.currency,
    required this.translations,
    required this.onOpenEntry,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelection,
  });

  final DateTime month;
  final Stream<List<Expense>> Function(DateTime month) watchExpenses;
  final List<Budget> allBudgets;
  final Map<String, int> budgetProgress;
  final String currency;
  final Translations? translations;
  final Future<void> Function({String? expenseId}) onOpenEntry;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Expense expense) onToggleSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<Expense>>(
      stream: watchExpenses(month),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorRetry(
            onRetry: () {},
            message: translations?.t('dashboard.error_load_month') ?? 'Could not load this month.',
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final expenses = snapshot.data!;
        final colors = context.appColors;
        final budgetRepo = ref.read(budgetRepositoryProvider);
        final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final active = allBudgets.where((b) => budgetRepo.isActiveForMonth(b, monthKey)).toList();
        final days = _groupByDay(expenses, currency, translations);
        final totals = _Totals.of(expenses, currency);

        final content = <Widget>[
          if (active.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.smMd),
              child: Text(
                (translations?.t('dashboard.active_budgets') ?? 'Active budgets').toUpperCase(),
                style: appHeaderStyle(colors),
              ),
            ),
            _BudgetGrid(budgets: active.take(4).toList(), progress: budgetProgress),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (!selectionMode) ...[
            _RecurringDueSection(translations: translations),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (expenses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(child: Text(translations?.t('dashboard.no_transactions') ?? 'No transactions')),
            )
          else
            for (final group in days) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.xs, AppSpacing.smMd),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(group.label, style: appHeaderStyle(colors)),
                    Text(
                      _signed(group.total, currency),
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                            color: group.total >= 0 ? context.semanticColors.income : colors.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ],
                ),
              ),
              for (final expense in group.items)
                _ExpenseRow(
                  expense: expense,
                  translations: translations,
                  selectionMode: selectionMode,
                  selected: selectedIds.contains(expense.id),
                  onTap: () => selectionMode ? onToggleSelection(expense) : onOpenEntry(expenseId: expense.id),
                  onLongPress: () => onToggleSelection(expense),
                ),
              const SizedBox(height: AppSpacing.smMd),
            ],
        ];

        return CustomScrollView(
          // Always scrollable so the hero can collapse even on short months.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Scroll-driven collapsing hero: shrinkOffset (0 → maxExtent-minExtent)
            // is the animation clock — the scroll position IS the value.
            SliverPersistentHeader(
              pinned: true,
              delegate: _HeroHeaderDelegate(totals: totals, currency: currency, translations: translations),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxxl),
              sliver: SliverList.list(children: content),
            ),
          ],
        );
      },
    );
  }
}

/// Pinned collapsing hero. [shrinkOffset] maps linearly to t (0 = expanded,
/// 1 = collapsed): the scroll drives the balance shrink and the Income/Spent
/// tiles folding away, simultaneously, 1:1 with the finger.
class _HeroHeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeroHeaderDelegate({required this.totals, required this.currency, required this.translations});

  final _Totals totals;
  final String currency;
  final Translations? translations;

  static const double _min = 88;
  static const double _max = 244;

  @override
  double get minExtent => _min;
  @override
  double get maxExtent => _max;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (_max - _min)).clamp(0.0, 1.0);
    return _BalanceHeader(totals: totals, currency: currency, t: t, translations: translations);
  }

  @override
  bool shouldRebuild(_HeroHeaderDelegate old) =>
      old.totals.spent != totals.spent ||
      old.totals.income != totals.income ||
      old.currency != currency ||
      old.translations != translations;
}

/// A day bucket of transactions in display order, with its signed total.
class _DayGroup {
  _DayGroup(this.label);
  final String label;
  final List<Expense> items = [];
  int total = 0;
}

int _signedCents(Expense e) => switch (e.type) {
      'income' => e.amount,
      'refund' => e.amount,
      _ => -e.amount,
    };

String _signed(int cents, String currency) {
  final sign = cents > 0 ? '+' : '';
  return '$sign${formatMoney(cents, currency)}';
}

String _dayLabel(DateTime date, Translations? translations) {
  final now = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return (translations?.t('dashboard.today') ?? 'Today').toUpperCase();
  if (diff == 1) return (translations?.t('dashboard.yesterday') ?? 'Yesterday').toUpperCase();
  return DateFormat.MMMEd().format(date).toUpperCase();
}

List<_DayGroup> _groupByDay(List<Expense> expenses, String currency, Translations? translations) {
  final groups = <_DayGroup>[];
  final index = <String, int>{};
  for (final e in expenses) {
    final key = '${e.date.year}-${e.date.month}-${e.date.day}';
    var i = index[key];
    if (i == null) {
      i = groups.length;
      index[key] = i;
      groups.add(_DayGroup(_dayLabel(e.date, translations)));
    }
    groups[i].items.add(e);
    if (e.currency == currency) groups[i].total += _signedCents(e);
  }
  return groups;
}

/// The dashboard's active-budgets preview: a fixed 2-column grid, capped at 4
/// budgets. 1–2 budgets fill a single row; 3–4 fill a 2×2 grid, padding the
/// trailing gap with an empty slot so cells stay aligned. Every cell taps
/// through to the Budgets tab.
class _BudgetGrid extends StatelessWidget {
  const _BudgetGrid({required this.budgets, required this.progress});

  final List<Budget> budgets;
  final Map<String, int> progress;

  @override
  Widget build(BuildContext context) {
    final rows = budgets.length <= 2 ? 1 : 2;
    final cells = <Widget?>[
      for (final b in budgets) _BudgetProgressTile(budget: b, spent: progress[b.id] ?? 0),
    ];
    while (cells.length < rows * 2) {
      cells.add(null);
    }

    Widget cell(Widget? w) => Expanded(child: w ?? const _BudgetPlaceholder());

    return Column(
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cell(cells[r * 2]),
                const SizedBox(width: AppSpacing.sm),
                cell(cells[r * 2 + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Empty slot filling a trailing gap in the budget grid: a plain rounded grey
/// patch (theme-aware, no content) that reads as "something missing here" while
/// keeping the row aligned. Stretched to a tile's height by the row.
class _BudgetPlaceholder extends StatelessWidget {
  const _BudgetPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        color: colors.surfaceAlt.withValues(alpha: 0.4),
      ),
    );
  }
}

class _BudgetProgressTile extends ConsumerWidget {
  const _BudgetProgressTile({required this.budget, required this.spent});

  final Budget budget;
  final int spent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratio = budget.amount == 0 ? 0.0 : (spent / budget.amount).clamp(0.0, 1.0);
    final over = spent > budget.amount;
    final semantic = context.semanticColors;
    final colors = context.appColors;
    final theme = Theme.of(context);
    final categoryColor = chartPalette[(budget.categoryId ?? budget.id).hashCode % chartPalette.length];
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: InkWell(
        onTap: () => context.go('/budgets'),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            border: Border.all(color: colors.borderSoft, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      budget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${budget.amount == 0 ? 0 : (spent / budget.amount * 100).round()}%',
                    style: theme.textTheme.bodySmall!.copyWith(
                          color: over ? semantic.over : colors.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ThinProgressBar(value: ratio, fillColor: over ? semantic.over : categoryColor),
            ],
          ),
        ),
      ),
    );
  }
}

/// Transaction row as a hairline card: uppercase category line, title, and the
/// signed amount in the display face (income emerald / expense rose / refund
/// neutral).
class _ExpenseRow extends ConsumerWidget {
  const _ExpenseRow({
    required this.expense,
    required this.translations,
    required this.onTap,
    required this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  final Expense expense;
  final Translations? translations;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final sign = switch (expense.type) {
      'income' => '+',
      'refund' => '±',
      _ => '-',
    };
    final color = context.amountColorForType(expense.type);
    final title = expense.description?.isNotEmpty == true ? expense.description! : expense.type;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: selected ? colors.mutedFill(0.5) : colors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.smMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              border: Border.all(color: colors.borderSoft, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (selectionMode) ...[
                  Checkbox(value: selected, onChanged: (_) => onTap()),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<String?>(
                        future: _categoryLabel(ref),
                        builder: (context, snapshot) {
                          final label = snapshot.data;
                          if (label == null || label.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              label.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                                color: colors.textMuted,
                              ),
                            ),
                          );
                        },
                      ),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '$sign${formatMoney(expense.amount, expense.currency)}',
                  style: appDisplay(colors, fontSize: 18, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _categoryLabel(WidgetRef ref) async {
    if (expense.categoryId == null || translations == null) return null;
    final categories = await ref.read(referenceDataCacheProvider).categories();
    final match = categories.where((c) => c.id == expense.categoryId);
    if (match.isEmpty) return null;
    return displayNameFor(translations!, name: match.first.name, isDefault: match.first.isDefault);
  }
}

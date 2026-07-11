import 'dart:ui' show lerpDouble;

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/display_name.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/expense_repository.dart';
import '../widgets/amount_text.dart';
import '../widgets/app_card.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/entity_form_dialog.dart' show chartPalette;
import '../widgets/month_header_bar.dart';
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

/// Scroll offset (px) over which the hero fully collapses.
const double _kCollapseDistance = 40;

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late final DateTime _baseMonth;
  late final PageController _pageController;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// 0 = hero expanded, 1 = fully collapsed. Driven by the active page scroll.
  final ValueNotifier<double> _collapse = ValueNotifier(0);

  final Map<String, List<Expense>> _expenseCache = {};
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
  String get _monthKey => _monthKeyOf(_month);

  @override
  void initState() {
    super.initState();
    _baseMonth = DateTime(_month.year, _month.month);
    _pageController = PageController(initialPage: _kInitialPage);
    _loadBudgets();
    _prefetchAdjacent();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _collapse.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) => DateTime(_baseMonth.year, _baseMonth.month + (page - _kInitialPage));

  DateTime _monthBounds(DateTime month) => DateTime(month.year, month.month + 1, 0);

  Future<List<Expense>> _fetchMonth(DateTime month) async {
    final key = _monthKeyOf(month);
    if (_expenseCache.containsKey(key)) return _expenseCache[key]!;
    final repo = ref.read(expenseRepositoryProvider);
    final expenses = await repo.listAll(
      filters: ExpenseFilters(dateFrom: DateTime(month.year, month.month, 1), dateTo: _monthBounds(month)),
    );
    _expenseCache[key] = expenses;
    return expenses;
  }

  Future<void> _prefetchAdjacent() async {
    await _fetchMonth(DateTime(_month.year, _month.month - 1));
    await _fetchMonth(DateTime(_month.year, _month.month + 1));
  }

  Future<void> _loadBudgets() async {
    final budgetRepo = ref.read(budgetRepositoryProvider);
    final allBudgets = await budgetRepo.listAll();
    final progress = <String, int>{};
    for (final budget in allBudgets) {
      progress[budget.id] = await budgetRepo.calculateProgress(budget);
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
    _collapse.value = 0;
    setState(() => _month = _monthForPage(page));
    _prefetchAdjacent();
  }

  /// Catch vertical scroll from the active page's ListView and map it to the
  /// collapse factor. Horizontal (PageView) notifications are ignored.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical) {
      _collapse.value = (n.metrics.pixels / _kCollapseDistance).clamp(0.0, 1.0);
    }
    return false;
  }

  Future<void> _openEntry({String? expenseId}) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(builder: (_) => ExpenseEntryScreen(expenseId: expenseId)),
    );
    if (saved == true) {
      setState(() => _expenseCache.remove(_monthKey));
      _loadBudgets();
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete transactions',
      message: 'Delete $count selected transaction(s)?',
      destructive: true,
    );
    if (!confirmed) return;
    final repo = ref.read(expenseRepositoryProvider);
    for (final id in _selectedIds) {
      await repo.delete(id);
    }
    setState(() {
      _selectedIds.clear();
      _expenseCache.clear();
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
      appBar: AppBar(
        title: _selectionMode ? Text('${_selectedIds.length} selected') : null,
        centerTitle: true,
        leading: _selectionMode
            ? IconButton(icon: const Icon(LucideIcons.x300), onPressed: () => setState(() => _selectedIds.clear()))
            : null,
        actions: _selectionMode
            ? [IconButton(icon: const Icon(LucideIcons.trash2300), onPressed: _deleteSelected)]
            : null,
      ),
      floatingActionButton: PressableScale(
        onTap: () => _openEntry(),
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
      body: Column(
        children: [
          MonthHeaderBar(month: _month, onChangeMonth: _changeMonth),
          // Shared collapsing hero — totals for the current month.
          FutureBuilder<List<Expense>>(
            future: _fetchMonth(_month),
            builder: (context, snapshot) {
              final totals = _Totals.of(snapshot.data ?? const [], currency);
              return ValueListenableBuilder<double>(
                valueListenable: _collapse,
                builder: (context, t, _) => _BalanceHeader(totals: totals, currency: currency, t: t),
              );
            },
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final month = _monthForPage(index);
                  return _MonthPage(
                    key: ValueKey(_monthKeyOf(month)),
                    month: month,
                    fetchExpenses: _fetchMonth,
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
          ),
        ],
      ),
    );
  }
}

/// Signed monthly totals in the profile currency (accounting rule: expense
/// subtracts, refund adds back, income is tracked separately).
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
  const _BalanceHeader({required this.totals, required this.currency, required this.t});

  final _Totals totals;
  final String currency;
  final double t;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final semantic = context.semanticColors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        lerpDouble(AppSpacing.md, AppSpacing.sm, t)!,
        AppSpacing.lg,
        lerpDouble(0, AppSpacing.smMd, t)!,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider.withValues(alpha: t), width: 1)),
      ),
      child: Column(
        children: [
          Text(
            'Total Balance',
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
                          label: 'Income',
                          value: totals.income,
                          currency: currency,
                          icon: LucideIcons.arrowDownRight,
                          color: semantic.income,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _StatTile(
                          label: 'Spent',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: iconChipBackground(color), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: AppSpacing.smMd),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: AppSpacing.xs),
          AmountText(
            amountCents: value,
            currency: currency,
            style: appDisplay(colors, fontSize: 20),
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
    required this.fetchExpenses,
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
  final Future<List<Expense>> Function(DateTime month) fetchExpenses;
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
    return FutureBuilder<List<Expense>>(
      future: fetchExpenses(month),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final expenses = snapshot.data!;
        final colors = context.appColors;
        final budgetRepo = ref.read(budgetRepositoryProvider);
        final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final active = allBudgets.where((b) => budgetRepo.isActiveForMonth(b, monthKey)).toList();
        final days = _groupByDay(expenses, currency);

        return ListView(
          // Always scrollable so the hero can collapse even on short months.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxxl),
          children: [
            if (active.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.smMd),
                child: Text('ACTIVE BUDGETS', style: appHeaderStyle(colors)),
              ),
              AppCard(
                child: Column(
                  children: [
                    for (final budget in active)
                      _BudgetProgressTile(budget: budget, spent: budgetProgress[budget.id] ?? 0),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (expenses.isEmpty)
              const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: Text('No transactions')))
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
          ],
        );
      },
    );
  }
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
  final v = cents / 100;
  final sign = cents > 0 ? '+' : '';
  return '$sign${v.toStringAsFixed(2)} $currency';
}

String _dayLabel(DateTime date) {
  final now = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'TODAY';
  if (diff == 1) return 'YESTERDAY';
  return DateFormat.MMMEd().format(date).toUpperCase();
}

List<_DayGroup> _groupByDay(List<Expense> expenses, String currency) {
  final groups = <_DayGroup>[];
  final index = <String, int>{};
  for (final e in expenses) {
    final key = '${e.date.year}-${e.date.month}-${e.date.day}';
    var i = index[key];
    if (i == null) {
      i = groups.length;
      index[key] = i;
      groups.add(_DayGroup(_dayLabel(e.date)));
    }
    groups[i].items.add(e);
    if (e.currency == currency) groups[i].total += _signedCents(e);
  }
  return groups;
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
    final categoryColor = chartPalette[(budget.categoryId ?? budget.id).hashCode % chartPalette.length];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(budget.name, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          ThinProgressBar(value: ratio, fillColor: over ? semantic.over : categoryColor),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${(spent / 100).toStringAsFixed(2)} / ${(budget.amount / 100).toStringAsFixed(2)} ${budget.currency}',
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: over ? semantic.over : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
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
                  '$sign${(expense.amount / 100).toStringAsFixed(2)} ${expense.currency}',
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

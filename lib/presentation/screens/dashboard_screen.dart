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
import '../widgets/confirm_dialog.dart';
import 'expense_entry/expense_entry_screen.dart';

/// Month-scoped overview (plan §3.3): swipe/arrow month navigation, totals in
/// the profile currency, active budgets (including `total` — web divergence,
/// plan §8), and the month's transaction list.
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
    setState(() => _month = _monthForPage(page));
    _prefetchAdjacent();
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

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : Text(translations?.t('nav.dashboard') ?? 'Dashboard'),
        leading: _selectionMode
            ? IconButton(icon: const Icon(LucideIcons.x300), onPressed: () => setState(() => _selectedIds.clear()))
            : null,
        actions: _selectionMode
            ? [IconButton(icon: const Icon(LucideIcons.trash2300), onPressed: _deleteSelected)]
            : null,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEntry(),
        child: const Icon(LucideIcons.plus300),
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(LucideIcons.chevronLeft300), onPressed: () => _changeMonth(-1)),
              Text(DateFormat.yMMMM().format(_month), style: Theme.of(context).textTheme.titleMedium),
              IconButton(icon: const Icon(LucideIcons.chevronRight300), onPressed: () => _changeMonth(1)),
            ],
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
        final balance = income - spent;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final semantic = isDark ? AppSemanticColors.dark : AppSemanticColors.light;
        final colors = isDark ? AppColors.dark : AppColors.light;
        final budgetRepo = ref.read(budgetRepositoryProvider);
        final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
        final active = allBudgets.where((b) => budgetRepo.isActiveForMonth(b, monthKey)).toList();

        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _TotalTile(label: 'Spent', value: spent, currency: currency, color: semantic.expense),
                  _TotalTile(label: 'Income', value: income, currency: currency, color: semantic.income),
                  _TotalTile(label: 'Balance', value: balance, currency: currency, color: colors.text),
                ],
              ),
            ),
            if (active.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Active budgets', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              for (final budget in active)
                _BudgetProgressTile(
                  budget: budget,
                  spent: budgetProgress[budget.id] ?? 0,
                ),
            ],
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Transactions', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (expenses.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No transactions')),
            for (final expense in expenses)
              _ExpenseRow(
                expense: expense,
                translations: translations,
                selectionMode: selectionMode,
                selected: selectedIds.contains(expense.id),
                onTap: () => selectionMode ? onToggleSelection(expense) : onOpenEntry(expenseId: expense.id),
                onLongPress: () => onToggleSelection(expense),
              ),
          ],
        );
      },
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({required this.label, required this.value, required this.currency, required this.color});

  final String label;
  final int value;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            '${(value / 100).toStringAsFixed(2)} $currency',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final semantic = isDark ? AppSemanticColors.dark : AppSemanticColors.light;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(budget.name),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: ratio,
            color: over ? semantic.over : Theme.of(context).colorScheme.primary,
          ),
          Text(
            '${(spent / 100).toStringAsFixed(2)} / ${(budget.amount / 100).toStringAsFixed(2)} ${budget.currency}',
            style: TextStyle(
              color: over ? semantic.over : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

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
    final sign = switch (expense.type) {
      'income' => '+',
      'refund' => '±',
      _ => '-',
    };
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final semantic = isDark ? AppSemanticColors.dark : AppSemanticColors.light;
    final color = switch (expense.type) {
      'income' => semantic.income,
      'refund' => semantic.refund,
      _ => semantic.expense,
    };
    final title = expense.description?.isNotEmpty == true ? expense.description! : expense.type;

    return ListTile(
      selected: selected,
      leading: selectionMode ? Checkbox(value: selected, onChanged: (_) => onTap()) : null,
      title: Text(title),
      subtitle: FutureBuilder<String?>(
        future: _categoryLabel(ref),
        builder: (context, snapshot) => Text(snapshot.data ?? ''),
      ),
      trailing: Text(
        '$sign${(expense.amount / 100).toStringAsFixed(2)} ${expense.currency}',
        style: TextStyle(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      onTap: onTap,
      onLongPress: onLongPress,
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

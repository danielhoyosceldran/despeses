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

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  final Map<String, List<Expense>> _expenseCache = {};
  List<Expense> _expenses = [];
  List<Budget> _allBudgets = [];
  Map<String, int> _budgetProgress = {};
  bool _loading = true;

  String get _monthKey => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
    _prefetchAdjacent();
  }

  DateTime _monthBounds(DateTime month) => DateTime(month.year, month.month + 1, 0);

  Future<List<Expense>> _fetchMonth(DateTime month) async {
    final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
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

  Future<void> _load() async {
    setState(() => _loading = true);
    final expenses = await _fetchMonth(_month);
    final budgetRepo = ref.read(budgetRepositoryProvider);
    final allBudgets = await budgetRepo.listAll();
    final active = allBudgets.where((b) => budgetRepo.isActiveForMonth(b, _monthKey)).toList();
    final progress = <String, int>{};
    for (final budget in active) {
      progress[budget.id] = await budgetRepo.calculateProgress(budget);
    }
    if (!mounted) return;
    setState(() {
      _expenses = expenses;
      _allBudgets = active;
      _budgetProgress = progress;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
    _prefetchAdjacent();
  }

  Future<void> _openEntry({String? expenseId}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ExpenseEntryScreen(expenseId: expenseId)),
    );
    if (saved == true) {
      _expenseCache.remove(_monthKey);
      _load();
    }
  }

  Future<void> _delete(Expense expense) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete transaction',
      message: 'Delete this transaction?',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(expenseRepositoryProvider).delete(expense.id);
    _expenseCache.remove(_monthKey);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;
    final profileAsync = ref.watch(profileStreamProvider);
    final currency = profileAsync.asData?.value.currency ?? 'EUR';

    var spent = 0;
    var income = 0;
    for (final e in _expenses) {
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

    return Scaffold(
      appBar: AppBar(title: Text(translations?.t('nav.dashboard') ?? 'Dashboard')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEntry(),
        child: const Icon(Icons.add),
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 200) _changeMonth(-1);
          if (velocity < -200) _changeMonth(1);
        },
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1)),
                      Text(DateFormat.yMMMM().format(_month), style: Theme.of(context).textTheme.titleMedium),
                      IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeMonth(1)),
                    ],
                  ),
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
                  if (_allBudgets.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text('Active budgets', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    for (final budget in _allBudgets)
                      _BudgetProgressTile(
                        budget: budget,
                        spent: _budgetProgress[budget.id] ?? 0,
                      ),
                  ],
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('Transactions', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (_expenses.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No transactions')),
                  for (final expense in _expenses)
                    _ExpenseRow(
                      expense: expense,
                      translations: translations,
                      onTap: () => _openEntry(expenseId: expense.id),
                      onDelete: () => _delete(expense),
                    ),
                ],
              ),
      ),
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
    required this.onDelete,
  });

  final Expense expense;
  final Translations? translations;
  final VoidCallback onTap;
  final VoidCallback onDelete;

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
      title: Text(title),
      subtitle: FutureBuilder<String?>(
        future: _categoryLabel(ref),
        builder: (context, snapshot) => Text(snapshot.data ?? ''),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$sign${(expense.amount / 100).toStringAsFixed(2)} ${expense.currency}',
            style: TextStyle(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
        ],
      ),
      onTap: onTap,
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

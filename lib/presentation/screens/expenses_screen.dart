import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/expense_repository.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/expense_filter_sheet.dart';
import 'expense_entry/expense_entry_screen.dart';

/// Full transaction list (plan §3.4): paginated (100/page, "load more"),
/// SQL-only filters, tap opens the rich entry for editing.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  ExpenseFilters _filters = const ExpenseFilters();
  final List<Expense> _expenses = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _expenses.clear();
      _page = 0;
      _hasMore = true;
    });
    final page = await ref.read(expenseRepositoryProvider).list(filters: _filters, page: 0);
    setState(() {
      _expenses.addAll(page);
      _hasMore = page.length == ExpenseRepository.pageSize;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    final nextPage = _page + 1;
    final page = await ref.read(expenseRepositoryProvider).list(filters: _filters, page: nextPage);
    setState(() {
      _page = nextPage;
      _expenses.addAll(page);
      _hasMore = page.length == ExpenseRepository.pageSize;
    });
  }

  Future<void> _openFilters() async {
    final translations = await ref.read(translationsProvider.future);
    final cache = ref.read(referenceDataCacheProvider);
    final categories = await cache.categories();
    final tags = await cache.tags();
    final paymentMethods = await cache.paymentMethods();
    final events = await cache.events();
    final projects = await cache.projects();
    if (!mounted) return;
    final result = await showExpenseFilterSheet(
      context,
      initial: _filters,
      categories: categories,
      tags: tags,
      paymentMethods: paymentMethods,
      events: events,
      projects: projects,
      translations: translations,
    );
    if (result != null) {
      setState(() => _filters = result);
      _reload();
    }
  }

  Future<void> _openEntry({String? expenseId}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ExpenseEntryScreen(expenseId: expenseId)),
    );
    if (saved == true) _reload();
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
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final t = translationsAsync.asData?.value;
    final hasActiveFilters = _filters.type != null ||
        _filters.categoryId != null ||
        _filters.tagId != null ||
        _filters.paymentMethodId != null ||
        _filters.eventId != null ||
        _filters.projectId != null ||
        _filters.dateFrom != null ||
        _filters.dateTo != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(t?.t('nav.expenses') ?? 'Expenses'),
        actions: [
          IconButton(
            icon: Icon(hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
            onPressed: _openFilters,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _openEntry(), child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _expenses.isEmpty
              ? const Center(child: Text('No transactions'))
              : ListView.builder(
                  itemCount: _expenses.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _expenses.length) {
                      if (!_hasMore) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: TextButton(onPressed: _loadMore, child: const Text('Load more')),
                        ),
                      );
                    }
                    final expense = _expenses[index];
                    return _ExpenseTile(
                      expense: expense,
                      onTap: () => _openEntry(expenseId: expense.id),
                      onDelete: () => _delete(expense),
                    );
                  },
                ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({required this.expense, required this.onTap, required this.onDelete});

  final Expense expense;
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
      subtitle: Text(DateFormat.yMMMd().format(expense.date)),
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
}

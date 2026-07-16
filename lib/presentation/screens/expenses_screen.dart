import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format/money.dart';
import '../../core/navigation/bottom_up_route.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/expense_repository.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/drag_up_fab.dart';
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
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      bottomUpRoute(ExpenseEntryScreen(expenseId: expenseId)),
    );
    if (saved == true) _reload();
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
    setState(() => _selectedIds.clear());
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFilters = _filters.type != null ||
        _filters.categoryId != null ||
        _filters.tagId != null ||
        _filters.paymentMethodId != null ||
        _filters.eventId != null ||
        _filters.projectId != null ||
        _filters.dateFrom != null ||
        _filters.dateTo != null;

    final t = ref.watch(translationsProvider).asData?.value;

    return Scaffold(
      floatingActionButton: DragUpFab(
        pageBuilder: (_, close) => ExpenseEntryScreen(onClose: close),
        onResult: (saved) {
          if (saved == true) _reload();
        },
        child: const Icon(LucideIcons.plus300),
      ),
      body: Column(
        children: [
          AppTopBar(
            title: t?.t('nav.expenses') ?? 'Expenses',
            selectionCount: _selectedIds.length,
            onClearSelection: () => setState(() => _selectedIds.clear()),
            onDeleteSelection: _deleteSelected,
            actions: [
              TopBarCircleButton(
                icon: LucideIcons.filter300,
                color: hasActiveFilters ? context.appColors.accent : null,
                onTap: _openFilters,
              ),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _expenses.isEmpty
                    ? const Center(child: Text('No transactions'))
                    : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
                  itemCount: _expenses.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _expenses.length) {
                      if (!_hasMore) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Center(
                          child: TextButton(onPressed: _loadMore, child: const Text('Load more')),
                        ),
                      );
                    }
                    final expense = _expenses[index];
                    return _ExpenseTile(
                      expense: expense,
                      selectionMode: _selectionMode,
                      selected: _selectedIds.contains(expense.id),
                      onTap: () =>
                          _selectionMode ? _toggleSelection(expense) : _openEntry(expenseId: expense.id),
                      onLongPress: () => _toggleSelection(expense),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({
    required this.expense,
    required this.onTap,
    required this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  final Expense expense;
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
    final colors = context.appColors;
    final color = context.amountColorForType(expense.type);
    final title = expense.description?.isNotEmpty == true ? expense.description! : expense.type;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusButton),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        selected: selected,
        leading: selectionMode ? Checkbox(value: selected, onChanged: (_) => onTap()) : null,
        title: Text(title),
        subtitle: Text(DateFormat.yMMMd().format(expense.date)),
        trailing: Text(
          '$sign${formatMoney(expense.amount, expense.currency)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

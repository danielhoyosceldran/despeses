import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/translations.dart';
import '../../core/navigation/bottom_up_route.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/expense_repository.dart';
import '../../domain/search/transaction_search.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/day_grouped_list.dart';
import '../widgets/drag_up_fab.dart';
import '../widgets/error_retry.dart';
import '../widgets/expense_filter_sheet.dart';
import '../widgets/expense_row.dart';
import 'expense_entry/expense_entry_screen.dart';

/// Transactions tab: free-text search + advanced filters over every
/// transaction, listed grouped by day like the Dashboard. Opens limited to the
/// current month; the "This month" chip toggles that range.
///
/// SQL applies the [ExpenseFilters]; the search box ([TransactionQuery]) then
/// narrows the result client-side, since its accent-insensitive text match
/// has no SQL equivalent. The list is live (`watchAll`) and built lazily.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  /// Branch index of this tab in the shell (see `appRouter`).
  static const tabIndex = 1;

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  late ExpenseFilters _filters = _withThisMonth(const ExpenseFilters());
  late Stream<List<Expense>> _stream = _watch();
  final TextEditingController _searchController = TextEditingController();
  TransactionQuery? _query;
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static (DateTime, DateTime) _thisMonthBounds() {
    final now = DateTime.now();
    return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0));
  }

  static ExpenseFilters _withThisMonth(ExpenseFilters filters) {
    final (from, to) = _thisMonthBounds();
    return filters.copyWith(dateFrom: () => from, dateTo: () => to);
  }

  /// Whether the date range is exactly the current calendar month.
  bool get _isThisMonth {
    final (from, to) = _thisMonthBounds();
    return _filters.dateFrom == from && _filters.dateTo == to;
  }

  /// Whether anything beyond the "This month" range is filtering, which tints
  /// the filter action.
  bool get _hasAdvancedFilters {
    final f = _filters;
    return f.types.isNotEmpty ||
        f.categoryIds.isNotEmpty ||
        f.tagIds.isNotEmpty ||
        f.paymentMethodIds.isNotEmpty ||
        f.eventIds.isNotEmpty ||
        f.projectIds.isNotEmpty ||
        f.amountMin != null ||
        f.amountMax != null ||
        (!_isThisMonth && (f.dateFrom != null || f.dateTo != null));
  }

  Stream<List<Expense>> _watch() => ref.read(expenseRepositoryProvider).watchAll(filters: _filters);

  void _setFilters(ExpenseFilters filters) {
    setState(() {
      _filters = filters;
      _stream = _watch();
    });
  }

  void _toggleThisMonth() {
    _setFilters(_isThisMonth
        ? _filters.copyWith(dateFrom: () => null, dateTo: () => null)
        : _withThisMonth(_filters));
  }

  void _onQueryChanged(String text) {
    final query = TransactionQuery.parse(text);
    setState(() => _query = query.isEmpty ? null : query);
  }

  void _toggleSelection(Expense expense) {
    setState(() {
      if (_selectedIds.contains(expense.id)) {
        _selectedIds.remove(expense.id);
      } else {
        _selectedIds.add(expense.id);
      }
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
    if (result == null) return;
    // An inverted range would silently match nothing: swap it and say so.
    var filters = result;
    final swapDates = filters.hasInvertedDates;
    if (swapDates) filters = filters.withSwappedDates();
    final swapAmounts = filters.hasInvertedAmounts;
    if (swapAmounts) filters = filters.withSwappedAmounts();
    _setFilters(filters);
    if (!mounted) return;
    if (swapDates) showAppToast(context, translations.t('common.dates_swapped'), variant: ToastVariant.warning);
    if (swapAmounts) showAppToast(context, translations.t('common.amounts_swapped'), variant: ToastVariant.warning);
  }

  Future<void> _openEntry({String? expenseId}) async {
    await Navigator.of(context, rootNavigator: true).push<bool>(
      bottomUpRoute(ExpenseEntryScreen(expenseId: expenseId)),
    );
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final t = ref.read(translationsProvider).asData?.value;
    final confirmed = await showConfirmDialog(
      context,
      title: t?.t('dashboard.delete_title') ?? 'Delete transactions',
      message: (t?.t('dashboard.delete_message') ?? 'Delete {{count}} selected transaction(s)?')
          .replaceAll('{{count}}', '$count'),
      destructive: true,
    );
    if (!confirmed) return;
    final repo = ref.read(expenseRepositoryProvider);
    for (final id in _selectedIds) {
      await repo.delete(id);
    }
    setState(() => _selectedIds.clear());
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).asData?.value;
    final currency = ref.watch(profileStreamProvider).asData?.value.currency ?? 'EUR';
    // Kept mounted by the shell while other tabs show: detach the live query
    // then, so writes elsewhere don't re-query and rebuild a hidden list.
    final visible = ref.watch(currentTabIndexProvider.select((index) => index == ExpensesScreen.tabIndex));
    final colors = context.appColors;

    return Scaffold(
      floatingActionButton: DragUpFab(
        pageBuilder: (_, close) => ExpenseEntryScreen(onClose: close),
        child: const Icon(LucideIcons.plus300),
      ),
      body: Column(
        children: [
          AppTopBar(
            title: t?.t('nav.expenses') ?? 'Transactions',
            selectionCount: _selectedIds.length,
            onClearSelection: () => setState(() => _selectedIds.clear()),
            onDeleteSelection: _deleteSelected,
            actions: [
              TopBarCircleButton(
                icon: LucideIcons.filter300,
                color: _hasAdvancedFilters ? colors.accent : null,
                onTap: _openFilters,
                semanticLabel: t?.t('a11y.filter') ?? 'Filter',
              ),
            ],
          ),
          if (!_selectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: _SearchField(
                      controller: _searchController,
                      translations: t,
                      onChanged: _onQueryChanged,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilterChip(
                    label: Text(t?.t('transactions.this_month') ?? 'This month'),
                    selected: _isThisMonth,
                    onSelected: (_) => _toggleThisMonth(),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Expense>>(
              stream: visible ? _stream : null,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorRetry(
                    onRetry: () => setState(() => _stream = _watch()),
                    retryLabel: t?.t('common.retry') ?? 'Retry',
                  );
                }
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final derived = _ListDerived.of(snapshot.data!, _query, currency, t);
                return _TransactionList(
                  derived: derived,
                  currency: currency,
                  translations: t,
                  filtering: _query != null || _hasAdvancedFilters || _isThisMonth,
                  selectionMode: _selectionMode,
                  selectedIds: _selectedIds,
                  onTap: (e) => _selectionMode ? _toggleSelection(e) : _openEntry(expenseId: e.id),
                  onLongPress: _toggleSelection,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Search pill: leading search icon, hint with the query syntax, and a clear
/// button while non-empty.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.translations, required this.onChanged});

  final TextEditingController controller;
  final Translations? translations;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: translations?.t('transactions.search_hint') ?? 'Search (text, >50, <20…)',
        hintMaxLines: 1,
        isDense: true,
        filled: true,
        fillColor: colors.mutedFill(0.5),
        prefixIcon: Icon(LucideIcons.search300, size: 16, color: colors.textMuted),
        prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        suffixIcon: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: Icon(LucideIcons.circleX300, size: 18, color: colors.textMuted),
                  tooltip: translations?.t('a11y.clear_search') ?? 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          borderSide: BorderSide(color: colors.accent, width: 1),
        ),
      ),
    );
  }
}

/// The searched transactions and their flattened lazy-list items, memoized
/// per stream snapshot so rebuilds that don't change the data (selection,
/// typing the same query) don't re-filter and re-group the whole list.
class _ListDerived {
  _ListDerived._(this.query, this.currency, this.translations, this.today, this.expenses, this.items);

  final TransactionQuery? query;
  final String currency;
  final Translations? translations;

  /// Day the "Today"/"Yesterday" labels were computed for.
  final DateTime today;
  final List<Expense> expenses;

  /// [DayGroup] header, then its [Expense] rows, then [dayGroupGap]; per day.
  final List<Object> items;

  static final _cache = Expando<_ListDerived>('transactionsDerived');

  static _ListDerived of(List<Expense> source, TransactionQuery? query, String currency, Translations? translations) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cached = _cache[source];
    if (cached != null &&
        identical(cached.query, query) &&
        cached.currency == currency &&
        identical(cached.translations, translations) &&
        cached.today == today) {
      return cached;
    }
    final expenses = query != null ? source.where(query.matches).toList() : source;
    final items = dayGroupedItems(expenses, currency, translations, yearIfNotCurrent: true);
    final derived = _ListDerived._(query, currency, translations, today, expenses, items);
    _cache[source] = derived;
    return derived;
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.derived,
    required this.currency,
    required this.translations,
    required this.filtering,
    required this.selectionMode,
    required this.selectedIds,
    required this.onTap,
    required this.onLongPress,
  });

  final _ListDerived derived;
  final String currency;
  final Translations? translations;

  /// Whether a search or filter is narrowing the list (picks the empty text).
  final bool filtering;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<Expense> onTap;
  final ValueChanged<Expense> onLongPress;

  @override
  Widget build(BuildContext context) {
    final expenses = derived.expenses;
    final items = derived.items;
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.fabClearance),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: ResultsSummaryHeader(expenses: expenses, currency: currency, translations: translations),
              ),
              if (expenses.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                      child: Text(
                        filtering
                            ? translations?.t('transactions.no_results') ?? 'No matching transactions'
                            : translations?.t('dashboard.no_transactions') ?? 'No transactions',
                      ),
                    ),
                  ),
                ),
              // Built lazily: only the day headers and rows on screen exist.
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item is Expense) {
                    return ExpenseRow(
                      key: ValueKey(item.id),
                      expense: item,
                      translations: translations,
                      selectionMode: selectionMode,
                      selected: selectedIds.contains(item.id),
                      onTap: () => onTap(item),
                      onLongPress: () => onLongPress(item),
                    );
                  }
                  if (item is DayGroup) return DayGroupHeader(group: item, currency: currency);
                  // dayGroupGap: spacing after a day's last row.
                  return const SizedBox(height: AppSpacing.smMd);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import 'analytics/analytics_math.dart';
import 'analytics/analytics_query.dart';
import 'category_repository.dart';

const _uuid = Uuid();

String monthKeyOf(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// Comparable ordinal for a `YYYY-MM` key: `year * 12 + month`. Compares months
/// numerically, so ordering is correct regardless of zero-padding.
int _monthOrdinal(String key) {
  final parts = key.split('-');
  return int.parse(parts[0]) * 12 + int.parse(parts[1]);
}

/// Every budget and its spent figure (by budget id) for one month.
class BudgetMonthProgress {
  const BudgetMonthProgress(this.budgets, this.spent);

  final List<Budget> budgets;
  final Map<String, int> spent;
}

class BudgetRepository {
  BudgetRepository(this._db, this._categories);

  final AppDatabase _db;
  final CategoryRepository _categories;

  Future<List<Budget>> listAll() {
    return _db.select(_db.budgets).get();
  }

  Future<String> create({
    required String name,
    String? categoryId,
    String? tagId,
    String? projectId,
    String? eventId,
    required int amountCents,
    required String currency,
    required String budgetType,
    String? startsMonth,
    String? endsMonth,
  }) async {
    final dimensionsSet =
        [categoryId, tagId, projectId, eventId].where((d) => d != null).length;
    if (dimensionsSet != 1) {
      throw ArgumentError('Exactly one dimension (category/tag/project/event) must be set.');
    }
    switch (budgetType) {
      case 'monthly':
        // Recurring every month: no time bounds.
        startsMonth = null;
        endsMonth = null;
      case 'range':
        if (startsMonth == null || endsMonth == null) {
          throw ArgumentError('A range budget requires both startsMonth and endsMonth.');
        }
        if (_monthOrdinal(endsMonth) < _monthOrdinal(startsMonth)) {
          throw ArgumentError('endsMonth must not be before startsMonth.');
        }
      default:
        throw ArgumentError("budgetType must be 'monthly' or 'range'.");
    }
    final id = _uuid.v4();
    await _db.into(_db.budgets).insert(
          BudgetsCompanion.insert(
            id: id,
            name: name,
            categoryId: Value(categoryId),
            tagId: Value(tagId),
            projectId: Value(projectId),
            eventId: Value(eventId),
            amount: amountCents,
            currency: currency,
            budgetType: budgetType,
            startsMonth: Value(startsMonth),
            endsMonth: Value(endsMonth),
          ),
        );
    return id;
  }

  /// In edit mode dimension/type/value are locked (plan §3.2) — only name and
  /// amount may change.
  Future<void> updateNameAndAmount(String id, {String? name, int? amountCents}) async {
    await (_db.update(_db.budgets)..where((b) => b.id.equals(id))).write(
      BudgetsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        amount: amountCents == null ? const Value.absent() : Value(amountCents),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.budgets)..where((b) => b.id.equals(id))).go();
  }

  /// `monthly` budgets recur every month from the month they were created in
  /// (they didn't exist before, so past months must not show them, let alone
  /// as exceeded). `range` budgets are active only within their [start, end]
  /// month window.
  bool isActiveForMonth(Budget budget, String monthKey) {
    switch (budget.budgetType) {
      case 'monthly':
        return _monthOrdinal(monthKey) >= _monthOrdinal(monthKeyOf(budget.createdAt));
      case 'range':
        final ordinal = _monthOrdinal(monthKey);
        final afterStart = ordinal >= _monthOrdinal(budget.startsMonth!);
        final beforeEnd = ordinal <= _monthOrdinal(budget.endsMonth!);
        return afterStart && beforeEnd;
      default:
        return false;
    }
  }

  /// Sums `expense` (+) and `refund` (-) over the budget's configured period;
  /// `income` is ignored. Recurses into category descendants so a budget on a
  /// parent category also counts its subcategories' expenses.
  ///
  /// Category budgets effectively ignore refunds: categories are per
  /// transaction type, so a refund never carries an expense category and never
  /// matches the filter. This is by design (backlog BL-009, option b) — refunds
  /// do count on tag/project/event budgets, whose dimensions span all types.
  ///
  /// For `monthly` budgets the period is a single month — the month of
  /// [inMonth] (defaults to the current month). `range` budgets ignore
  /// [inMonth] and sum across their whole window.
  Future<int> calculateProgress(Budget budget, {DateTime? inMonth}) async {
    return (await progressFor([budget], inMonth: inMonth))[budget.id] ?? 0;
  }

  /// [calculateProgress] for many budgets at once, keyed by budget id (BL-063).
  /// Instead of one query per budget, the spend of the union of every period
  /// is aggregated in SQL per month and per category/project/event (plus one
  /// query per month and tag for tag budgets, joined to `expense_tags` and
  /// date-filtered), then each budget sums the months of its own window.
  Future<Map<String, int>> progressFor(Iterable<Budget> budgets, {DateTime? inMonth}) async {
    final month = inMonth ?? DateTime.now();
    final result = <String, int>{};
    final byCurrency = <String, List<Budget>>{};
    for (final b in budgets) {
      byCurrency.putIfAbsent(b.currency, () => []).add(b);
    }
    for (final entry in byCurrency.entries) {
      result.addAll(await _progressInCurrency(entry.key, entry.value, month));
    }
    return result;
  }

  Future<Map<String, int>> _progressInCurrency(String currency, List<Budget> budgets, DateTime month) async {
    final windows = {for (final b in budgets) b.id: _periodBounds(b, month)};
    var from = windows.values.first.$1;
    var before = windows.values.first.$2;
    for (final (start, end) in windows.values) {
      if (start.isBefore(from)) from = start;
      if (end.isAfter(before)) before = end;
    }
    // One bucket per month of the union window; budget windows are whole
    // months, so each covers a contiguous run of buckets.
    final months = <DateTime>[];
    for (var m = from; m.isBefore(before); m = DateTime(m.year, m.month + 1)) {
      months.add(m);
    }
    int bucketOf(DateTime d) => (d.year * 12 + d.month) - (from.year * 12 + from.month);

    final hasDimension = budgets.any((b) => b.tagId == null);
    final tagIds = {for (final b in budgets) if (b.tagId != null) b.tagId!};
    final dimensionGroups = hasDimension
        ? await aggregateExpenses(
            _db,
            currency: currency,
            from: from,
            before: before,
            buckets: months,
            groupBy: const {AggregateBy.category, AggregateBy.project, AggregateBy.event},
            types: spendTypes,
          )
        : const <AmountGroup>[];
    final tagGroups = tagIds.isEmpty
        ? const <AmountGroup>[]
        : await aggregateExpenses(
            _db,
            currency: currency,
            from: from,
            before: before,
            buckets: months,
            groupBy: const {AggregateBy.tag},
            types: spendTypes,
            tagIds: tagIds,
          );
    final descendants =
        budgets.any((b) => b.categoryId != null) ? await _categories.descendantMap() : const <String, Set<String>>{};

    final result = <String, int>{};
    for (final b in budgets) {
      final (start, end) = windows[b.id]!;
      final first = bucketOf(start);
      final last = bucketOf(end); // exclusive
      final bool Function(AmountGroup) matches;
      final Iterable<AmountGroup> source;
      if (b.categoryId != null) {
        final ids = {b.categoryId!, ...?descendants[b.categoryId!]};
        matches = (g) => ids.contains(g.categoryId);
        source = dimensionGroups;
      } else if (b.projectId != null) {
        matches = (g) => g.projectId == b.projectId;
        source = dimensionGroups;
      } else if (b.eventId != null) {
        matches = (g) => g.eventId == b.eventId;
        source = dimensionGroups;
      } else {
        matches = (g) => g.tagId == b.tagId;
        source = tagGroups;
      }
      var total = 0;
      for (final g in source) {
        if (g.bucket >= first && g.bucket < last && matches(g)) {
          total += spentContribution(g.type, g.total);
        }
      }
      result[b.id] = total;
    }
    return result;
  }

  /// Every budget plus its progress for [month] (see [progressFor]), re-emitted
  /// whenever a table it depends on changes, so screens stay in sync without
  /// manual reloads (BL-063).
  Stream<BudgetMonthProgress> watchMonthProgress(DateTime month) {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.budgets, _db.expenses, _db.expenseTags, _db.categories},
        )
        .watch()
        .asyncMap((_) async {
      final budgets = await listAll();
      return BudgetMonthProgress(budgets, await progressFor(budgets, inMonth: month));
    });
  }

  /// Half-open `[start, end)` datetime window of a budget's period. `monthly`
  /// budgets span the month of [inMonth]; `range` budgets span their whole
  /// `[startsMonth, endsMonth]` window (end is the first day of the month
  /// after `endsMonth`).
  (DateTime, DateTime) _periodBounds(Budget budget, DateTime inMonth) {
    switch (budget.budgetType) {
      case 'range':
        final s = _firstOfMonthKey(budget.startsMonth!);
        final e = _firstOfMonthKey(budget.endsMonth!);
        return (s, DateTime(e.year, e.month + 1));
      case 'monthly':
      default:
        final start = DateTime(inMonth.year, inMonth.month);
        return (start, DateTime(start.year, start.month + 1));
    }
  }

  DateTime _firstOfMonthKey(String monthKey) {
    final parts = monthKey.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }
}

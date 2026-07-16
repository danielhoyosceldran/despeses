import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import 'analytics/analytics_math.dart';
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

  /// `monthly` budgets recur every month, so they are active in any month.
  /// `range` budgets are active only within their [start, end] month window.
  bool isActiveForMonth(Budget budget, String monthKey) {
    switch (budget.budgetType) {
      case 'monthly':
        return true;
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
  /// For `monthly` budgets the period is a single month — the month of
  /// [inMonth] (defaults to the current month). `range` budgets ignore
  /// [inMonth] and sum across their whole window.
  Future<int> calculateProgress(Budget budget, {DateTime? inMonth}) async {
    // Half-open date window [start, end) of the budget's period, so the DB
    // (not Dart) restricts rows — a `monthly` budget no longer loads the whole
    // category history just to keep one month (R2).
    final (start, end) = _periodBounds(budget, inMonth ?? DateTime.now());

    final query = _db.select(_db.expenses)
      ..where((e) => e.currency.equals(budget.currency))
      ..where((e) => e.type.isIn(['expense', 'refund']))
      ..where((e) => e.date.isBiggerOrEqualValue(start) & e.date.isSmallerThanValue(end));

    if (budget.categoryId != null) {
      final ids = {budget.categoryId!, ...await _categories.descendantIds(budget.categoryId!)};
      query.where((e) => e.categoryId.isIn(ids));
    } else if (budget.projectId != null) {
      query.where((e) => e.projectId.equals(budget.projectId!));
    } else if (budget.eventId != null) {
      query.where((e) => e.eventId.equals(budget.eventId!));
    }
    // tagId dimension is filtered below via expense_tags, after loading rows,
    // to keep this query shape uniform across dimensions.

    final expenses = await query.get();

    List<Expense> dimensionFiltered;
    if (budget.tagId != null) {
      final tagged = await (_db.select(_db.expenseTags)
            ..where((t) => t.tagId.equals(budget.tagId!)))
          .get();
      final taggedIds = tagged.map((t) => t.expenseId).toSet();
      dimensionFiltered = expenses.where((e) => taggedIds.contains(e.id)).toList();
    } else {
      dimensionFiltered = expenses;
    }

    var total = 0;
    for (final e in dimensionFiltered) {
      total += signedAmountOf(e);
    }
    return total;
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

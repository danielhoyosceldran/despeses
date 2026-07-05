import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import 'category_repository.dart';

const _uuid = Uuid();

class BudgetMonth {
  const BudgetMonth(this.year, this.month);

  factory BudgetMonth.fromJson(Map<String, dynamic> json) =>
      BudgetMonth(json['year'] as int, json['month'] as int);

  final int year;
  final int month;

  String get key => '$year-${month.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {'year': year, 'month': month};
}

String monthKeyOf(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

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
    List<BudgetMonth>? months,
    String? startsMonth,
    String? endsMonth,
  }) async {
    final dimensionsSet =
        [categoryId, tagId, projectId, eventId].where((d) => d != null).length;
    if (dimensionsSet != 1) {
      throw ArgumentError('Exactly one dimension (category/tag/project/event) must be set.');
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
            months: Value(months == null ? null : jsonEncode(months.map((m) => m.toJson()).toList())),
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

  List<BudgetMonth> decodeMonths(Budget budget) {
    if (budget.months == null) return const [];
    final list = jsonDecode(budget.months!) as List;
    return list.map((e) => BudgetMonth.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `total` budgets are always active (divergence vs spec — the web code shows
  /// them on the Dashboard regardless of navigated month).
  bool isActiveForMonth(Budget budget, String monthKey) {
    switch (budget.budgetType) {
      case 'total':
        return true;
      case 'range':
        final afterStart = monthKey.compareTo(budget.startsMonth!) >= 0;
        final beforeEnd = budget.endsMonth == null || monthKey.compareTo(budget.endsMonth!) <= 0;
        return afterStart && beforeEnd;
      case 'months':
        return decodeMonths(budget).any((m) => m.key == monthKey);
      default:
        return false;
    }
  }

  /// Sums `expense` (+) and `refund` (-) over the budget's own configured
  /// period; `income` is ignored. Recurses into category descendants so a
  /// budget on a parent category also counts its subcategories' expenses.
  Future<int> calculateProgress(Budget budget) async {
    final query = _db.select(_db.expenses)
      ..where((e) => e.currency.equals(budget.currency))
      ..where((e) => e.type.isIn(['expense', 'refund']));

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

    final periodFiltered = dimensionFiltered.where((e) => _withinPeriod(budget, e.date));

    var total = 0;
    for (final e in periodFiltered) {
      total += e.type == 'refund' ? -e.amount : e.amount;
    }
    return total;
  }

  bool _withinPeriod(Budget budget, DateTime date) {
    switch (budget.budgetType) {
      case 'total':
        return true;
      case 'range':
        final key = monthKeyOf(date);
        final afterStart = key.compareTo(budget.startsMonth!) >= 0;
        final beforeEnd = budget.endsMonth == null || key.compareTo(budget.endsMonth!) <= 0;
        return afterStart && beforeEnd;
      case 'months':
        return decodeMonths(budget).any((m) => m.key == monthKeyOf(date));
      default:
        return false;
    }
  }
}

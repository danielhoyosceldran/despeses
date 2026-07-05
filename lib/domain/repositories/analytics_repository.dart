import 'package:drift/drift.dart';

import '../../data/database.dart';
import 'category_repository.dart';

/// One pie slice: either a real category/tag, or the synthetic "direct"
/// bucket (expenses assigned straight to the parent category being drilled
/// into, plan §3.6).
class CategorySlice {
  const CategorySlice({required this.categoryId, required this.amountCents, this.isDirect = false});

  final String? categoryId;
  final int amountCents;
  final bool isDirect;
}

class TagSlice {
  const TagSlice({required this.tagId, required this.amountCents});

  final String tagId;
  final int amountCents;
}

/// Calculations for Analytics v1 (plan §3.6): month-scoped, profile-currency
/// only, `income` excluded, `refund` subtracts — same signed-sum rule as
/// budget progress (Fase 2).
class AnalyticsRepository {
  AnalyticsRepository(this._db, this._categories);

  final AppDatabase _db;
  final CategoryRepository _categories;

  DateTime _monthEnd(DateTime month) => DateTime(month.year, month.month + 1, 0, 23, 59, 59);

  int _signedSum(List<Expense> expenses) {
    var total = 0;
    for (final e in expenses) {
      if (e.type == 'income') continue;
      total += e.type == 'refund' ? -e.amount : e.amount;
    }
    return total;
  }

  Future<List<Expense>> _monthExpenses(DateTime month, String currency) {
    return (_db.select(_db.expenses)
          ..where((e) => e.currency.equals(currency))
          ..where((e) => e.date.isBiggerOrEqualValue(DateTime(month.year, month.month, 1)))
          ..where((e) => e.date.isSmallerOrEqualValue(_monthEnd(month))))
        .get();
  }

  /// Total for the month (expense - refund, income excluded).
  Future<int> monthTotal(DateTime month, String currency) async {
    return _signedSum(await _monthExpenses(month, currency));
  }

  /// One level of the category drill-down: a slice per direct child of
  /// [parentId] (aggregating that child's own descendants recursively), plus
  /// a "direct" slice for expenses assigned exactly to [parentId] itself.
  /// [parentId] `null` means the root level.
  Future<List<CategorySlice>> categoryBreakdown(DateTime month, String? parentId, String currency) async {
    final expenses = await _monthExpenses(month, currency);
    final children = await _categories.listChildren(parentId);

    final slices = <CategorySlice>[];
    for (final child in children) {
      final ids = {child.id, ...await _categories.descendantIds(child.id)};
      final matching = expenses.where((e) => e.categoryId != null && ids.contains(e.categoryId));
      final amount = _signedSum(matching.toList());
      if (amount != 0) slices.add(CategorySlice(categoryId: child.id, amountCents: amount));
    }

    final direct = expenses.where((e) => e.categoryId == parentId);
    final amount = _signedSum(direct.toList());
    if (amount != 0) slices.add(CategorySlice(categoryId: parentId, amountCents: amount, isDirect: true));

    return slices;
  }

  /// Flat per-tag totals. A multi-tag expense counts fully in each of its
  /// tags, so the sum of slices can exceed the month total (plan §3.6).
  Future<List<TagSlice>> tagBreakdown(DateTime month, String currency) async {
    final expenses = await _monthExpenses(month, currency);
    final expenseIds = expenses.map((e) => e.id).toSet();
    if (expenseIds.isEmpty) return [];

    final links = await (_db.select(_db.expenseTags)
          ..where((t) => t.expenseId.isIn(expenseIds)))
        .get();

    final expenseById = {for (final e in expenses) e.id: e};
    final byTag = <String, List<Expense>>{};
    for (final link in links) {
      final expense = expenseById[link.expenseId];
      if (expense == null) continue;
      byTag.putIfAbsent(link.tagId, () => []).add(expense);
    }

    return [
      for (final entry in byTag.entries)
        if (_signedSum(entry.value) != 0) TagSlice(tagId: entry.key, amountCents: _signedSum(entry.value)),
    ];
  }
}

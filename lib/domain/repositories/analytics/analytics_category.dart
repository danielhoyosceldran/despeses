import '../../../data/database.dart';
import '../category_repository.dart';
import 'analytics_math.dart';
import 'analytics_query.dart';

/// One category slice: the category and its aggregated amount (its own leaves
/// plus every descendant). Since categorization is leaf-only, there is no
/// separate "direct" bucket anymore.
class CategorySlice {
  const CategorySlice({required this.categoryId, required this.amountCents});

  final String categoryId;
  final int amountCents;
}

/// A ranked category with its share of the total and the average ticket.
class CategoryRankEntry {
  const CategoryRankEntry({
    required this.categoryId,
    required this.amountCents,
    required this.share,
    required this.averageTicketCents,
    required this.count,
  });

  final String categoryId;
  final int amountCents;
  final double share; // 0..1 of the level total
  final double averageTicketCents;
  final int count;
}

/// Category analytics for one transaction-type forest (expense/income/refund/
/// ahorro). Every method takes the [type] whose tree + transactions to use.
class CategoryAnalytics {
  CategoryAnalytics(this._db, this._categories);

  final AppDatabase _db;
  final CategoryRepository _categories;

  /// Transactions of [type] in [range] for [currency].
  Future<List<Expense>> _typeExpenses(DateRange range, String type, String currency) async {
    final all = await expensesInRange(_db, range, currency);
    return all.where((e) => e.type == type).toList();
  }

  /// One drill level: a slice per direct child of [parentId] (aggregating the
  /// child's whole subtree). [parentId] null = the roots of the [type] forest.
  Future<List<CategorySlice>> breakdown(
    DateRange range, {
    String? parentId,
    required String type,
    required String currency,
  }) async {
    final expenses = await _typeExpenses(range, type, currency);
    final children = await _categories.listChildren(parentId, type: type);
    final descendants = await _categories.descendantMap();

    final slices = <CategorySlice>[];
    for (final child in children) {
      final ids = {child.id, ...?descendants[child.id]};
      final amount = expenses
          .where((e) => e.categoryId != null && ids.contains(e.categoryId))
          .fold<int>(0, (sum, e) => sum + e.amount);
      if (amount != 0) slices.add(CategorySlice(categoryId: child.id, amountCents: amount));
    }
    return slices;
  }

  /// A3.3 — root categories ranked by amount, each with % of total and average
  /// ticket. Descending by amount.
  Future<List<CategoryRankEntry>> ranking(
    DateRange range, {
    required String type,
    required String currency,
  }) async {
    final expenses = await _typeExpenses(range, type, currency);
    final roots = await _categories.listChildren(null, type: type);
    final descendants = await _categories.descendantMap();

    final entries = <CategoryRankEntry>[];
    var total = 0;
    for (final root in roots) {
      final ids = {root.id, ...?descendants[root.id]};
      final matching = expenses.where((e) => e.categoryId != null && ids.contains(e.categoryId)).toList();
      final amount = matching.fold<int>(0, (sum, e) => sum + e.amount);
      if (amount == 0) continue;
      total += amount;
      entries.add(CategoryRankEntry(
        categoryId: root.id,
        amountCents: amount,
        share: 0, // filled below once total is known
        averageTicketCents: matching.isEmpty ? 0 : amount / matching.length,
        count: matching.length,
      ));
    }
    entries.sort((a, b) => b.amountCents.compareTo(a.amountCents));
    return [
      for (final e in entries)
        CategoryRankEntry(
          categoryId: e.categoryId,
          amountCents: e.amountCents,
          share: total == 0 ? 0 : e.amountCents / total,
          averageTicketCents: e.averageTicketCents,
          count: e.count,
        ),
    ];
  }

  /// A3.1 — for stacked bars: per month, the amount of each root category.
  /// Returns `month → (rootCategoryId → amount)`.
  Future<Map<DateTime, Map<String, int>>> monthlyByRoot(
    DateRange range, {
    required String type,
    required String currency,
  }) async {
    final expenses = await _typeExpenses(range, type, currency);
    final roots = await _categories.listChildren(null, type: type);
    final descendants = await _categories.descendantMap();
    final rootIds = <String, Set<String>>{
      for (final r in roots) r.id: {r.id, ...?descendants[r.id]},
    };

    final result = <DateTime, Map<String, int>>{
      for (final m in monthsIn(range)) m: {},
    };
    for (final e in expenses) {
      if (e.categoryId == null) continue;
      final month = DateTime(e.date.year, e.date.month, 1);
      final bucket = result[month];
      if (bucket == null) continue;
      for (final entry in rootIds.entries) {
        if (entry.value.contains(e.categoryId)) {
          bucket[entry.key] = (bucket[entry.key] ?? 0) + e.amount;
          break;
        }
      }
    }
    return result;
  }

  /// A3.4 — monthly trend of a single category (its whole subtree).
  Future<List<(DateTime, int)>> trend(
    String categoryId,
    DateRange range, {
    required String type,
    required String currency,
  }) async {
    final expenses = await _typeExpenses(range, type, currency);
    final ids = {categoryId, ...await _categories.descendantIds(categoryId)};
    // (single-category trend: one descendantIds lookup is fine here)
    final byMonth = <String, int>{};
    for (final e in expenses) {
      if (e.categoryId == null || !ids.contains(e.categoryId)) continue;
      final key = '${e.date.year}-${e.date.month}';
      byMonth[key] = (byMonth[key] ?? 0) + e.amount;
    }
    return [
      for (final m in monthsIn(range)) (m, byMonth['${m.year}-${m.month}'] ?? 0),
    ];
  }
}

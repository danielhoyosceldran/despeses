import '../../../data/database.dart';
import '../category_repository.dart';
import 'analytics_math.dart';
import 'analytics_query.dart';

/// Aggregated amount and transaction count of one category.
typedef CategoryTotal = ({int amount, int count});

/// One category slice: the category and its aggregated amount (its own leaves
/// plus every descendant). Since categorization is leaf-only, there is no
/// separate "direct" bucket anymore.
class CategorySlice {
  const CategorySlice({required this.categoryId, required this.amountCents, this.count = 0});

  final String categoryId;
  final int amountCents;

  /// Number of transactions aggregated into [amountCents].
  final int count;
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
/// Totals are aggregated per category in SQL (BL-062) and rolled up the
/// category tree in Dart.
class CategoryAnalytics {
  CategoryAnalytics(this._db, this._categories);

  final AppDatabase _db;
  final CategoryRepository _categories;

  /// Amount and count per category of the [type] transactions in [range].
  Future<Map<String, CategoryTotal>> _totals(DateRange range, String type, String currency) async {
    final groups = await aggregateInRange(_db, range, currency, groupBy: const {AggregateBy.category}, types: [type]);
    return totalsByCategory(groups);
  }

  /// Amount and count per category of [groups] (aggregated by category).
  /// Uncategorized groups are dropped.
  static Map<String, CategoryTotal> totalsByCategory(Iterable<AmountGroup> groups) {
    final totals = <String, CategoryTotal>{};
    for (final g in groups) {
      final id = g.categoryId;
      if (id == null) continue;
      final prev = totals[id];
      totals[id] = (amount: (prev?.amount ?? 0) + g.total, count: (prev?.count ?? 0) + g.count);
    }
    return totals;
  }

  /// Sum of [totals] over the category ids in [ids].
  static CategoryTotal _sumOver(Map<String, CategoryTotal> totals, Set<String> ids) {
    var amount = 0;
    var count = 0;
    for (final id in ids) {
      final t = totals[id];
      if (t == null) continue;
      amount += t.amount;
      count += t.count;
    }
    return (amount: amount, count: count);
  }

  /// One drill level: a slice per direct child of [parentId] (aggregating the
  /// child's whole subtree). [parentId] null = the roots of the [type] forest.
  Future<List<CategorySlice>> breakdown(
    DateRange range, {
    String? parentId,
    required String type,
    required String currency,
  }) async {
    final totals = await _totals(range, type, currency);
    final children = await _categories.listChildren(parentId, type: type);
    final descendants = await _categories.descendantMap();

    final slices = <CategorySlice>[];
    for (final child in children) {
      final sum = _sumOver(totals, {child.id, ...?descendants[child.id]});
      if (sum.amount != 0) {
        slices.add(CategorySlice(categoryId: child.id, amountCents: sum.amount, count: sum.count));
      }
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
    return rankingFrom(await _totals(range, type, currency), type: type);
  }

  /// [ranking] from already aggregated per-category [totals] of one [type].
  Future<List<CategoryRankEntry>> rankingFrom(Map<String, CategoryTotal> totals, {required String type}) async {
    final roots = await _categories.listChildren(null, type: type);
    final descendants = await _categories.descendantMap();

    final entries = <CategoryRankEntry>[];
    var total = 0;
    for (final root in roots) {
      final sum = _sumOver(totals, {root.id, ...?descendants[root.id]});
      final amount = sum.amount;
      if (amount == 0) continue;
      total += amount;
      entries.add(CategoryRankEntry(
        categoryId: root.id,
        amountCents: amount,
        share: 0, // filled below once total is known
        averageTicketCents: sum.count == 0 ? 0 : amount / sum.count,
        count: sum.count,
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
    final months = monthsIn(range);
    final groups = await aggregateInRange(
      _db,
      range,
      currency,
      buckets: months,
      groupBy: const {AggregateBy.category},
      types: [type],
    );
    final roots = await _categories.listChildren(null, type: type);
    final descendants = await _categories.descendantMap();
    // Category id → its root (the first root whose subtree contains it).
    final rootOf = <String, String>{};
    for (final r in roots) {
      for (final id in {r.id, ...?descendants[r.id]}) {
        rootOf.putIfAbsent(id, () => r.id);
      }
    }

    final result = <DateTime, Map<String, int>>{for (final m in months) m: {}};
    for (final g in groups) {
      final root = rootOf[g.categoryId];
      if (root == null) continue;
      final bucket = result[months[g.bucket]]!;
      bucket[root] = (bucket[root] ?? 0) + g.total;
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
    final months = monthsIn(range);
    final groups = await aggregateInRange(
      _db,
      range,
      currency,
      buckets: months,
      groupBy: const {AggregateBy.category},
      types: [type],
    );
    final ids = {categoryId, ...await _categories.descendantIds(categoryId)};
    final totals = List<int>.filled(months.length, 0);
    for (final g in groups) {
      if (ids.contains(g.categoryId)) totals[g.bucket] += g.total;
    }
    return [for (var i = 0; i < months.length; i++) (months[i], totals[i])];
  }
}

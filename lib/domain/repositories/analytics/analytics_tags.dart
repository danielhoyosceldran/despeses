import '../../../data/database.dart';
import 'analytics_math.dart';
import 'analytics_query.dart';

class TagSlice {
  const TagSlice({required this.tagId, required this.amountCents, this.savingsCents = 0, this.count = 0});
  final String tagId;

  /// Number of transactions carrying the tag (any type).
  final int count;

  /// Spent under the tag ([expenseOutflow]).
  final int amountCents;

  /// Savings set aside under the tag ([savingsSetAside]), shown apart.
  final int savingsCents;
}

/// Tag / tag-group analytics (Analytics › Tags y grupos, section A4). Amounts
/// are spent ([expenseOutflow]; savings reported separately); a multi-tag expense counts fully in each tag, so
/// slice sums can exceed the period total.
class TagAnalytics {
  TagAnalytics(this._db);

  final AppDatabase _db;

  /// Loads the month/range expenses plus their tag links, keyed for reuse.
  Future<(List<Expense>, List<ExpenseTag>)> _expensesAndLinks(DateRange range, String currency) async {
    final expenses = await expensesInRange(_db, range, currency);
    final ids = expenses.map((e) => e.id).toSet();
    if (ids.isEmpty) return (expenses, <ExpenseTag>[]);
    final links = await (_db.select(_db.expenseTags)..where((t) => t.expenseId.isIn(ids))).get();
    return (expenses, links);
  }

  /// Aggregated groups per tag id, summed in SQL (BL-062).
  Future<Map<String, List<AmountGroup>>> _groupsByTag(DateRange range, String currency) async {
    final groups = await aggregateInRange(_db, range, currency, groupBy: const {AggregateBy.tag});
    final byTag = <String, List<AmountGroup>>{};
    for (final g in groups) {
      byTag.putIfAbsent(g.tagId!, () => []).add(g);
    }
    return byTag;
  }

  /// A4 base — spent per tag, plus each tag's savings. Only tags with spending
  /// are returned (a tag with only savings has no slice).
  Future<List<TagSlice>> byTag(DateRange range, String currency) async {
    final grouped = await _groupsByTag(range, currency);
    return [
      for (final entry in grouped.entries)
        if (entry.value.spent != 0)
          TagSlice(
            tagId: entry.key,
            amountCents: entry.value.spent,
            savingsCents: entry.value.savings,
            count: entry.value.count,
          ),
    ];
  }

  /// A4.1 — spent per tag group (`tagGroupId → cents`).
  Future<Map<String, int>> byGroup(DateRange range, String currency) async {
    final byTag = await _groupsByTag(range, currency);
    final tags = await _db.select(_db.tags).get();
    final groupOf = {for (final t in tags) t.id: t.tagGroupId};

    final result = <String, int>{};
    for (final entry in byTag.entries) {
      final group = groupOf[entry.key];
      if (group != null) result[group] = (result[group] ?? 0) + entry.value.spent;
    }
    return result;
  }

  /// A4.3 — data quality: fraction of expense/refund transactions with no tag.
  Future<double> coverageGap(DateRange range, String currency) async {
    final (expenses, links) = await _expensesAndLinks(range, currency);
    final spendTxns = expenses.where((e) => e.type == 'expense' || e.type == 'refund').toList();
    if (spendTxns.isEmpty) return 0;
    final tagged = links.map((l) => l.expenseId).toSet();
    final untagged = spendTxns.where((e) => !tagged.contains(e.id)).length;
    return untagged / spendTxns.length;
  }

  /// A4.4 — heatmap tag × category: `tagId → (categoryId → signed cents)`.
  Future<Map<String, Map<String?, int>>> tagByCategory(DateRange range, String currency) async {
    final groups = await aggregateInRange(
      _db,
      range,
      currency,
      groupBy: const {AggregateBy.tag, AggregateBy.category},
      types: spendTypes,
    );
    final result = <String, Map<String?, int>>{};
    for (final g in groups) {
      final row = result.putIfAbsent(g.tagId!, () => {});
      row[g.categoryId] = (row[g.categoryId] ?? 0) + spentContribution(g.type, g.total);
    }
    return result;
  }
}

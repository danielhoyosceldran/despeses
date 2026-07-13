import '../../../data/database.dart';
import 'analytics_math.dart';
import 'analytics_query.dart';

class TagSlice {
  const TagSlice({required this.tagId, required this.amountCents});
  final String tagId;
  final int amountCents;
}

/// Tag / tag-group analytics (Analytics › Tags y grupos, section A4). Amounts
/// use the signed spend rule; a multi-tag expense counts fully in each tag, so
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

  /// A4 base — signed spend per tag.
  Future<List<TagSlice>> byTag(DateRange range, String currency) async {
    final (expenses, links) = await _expensesAndLinks(range, currency);
    final byId = {for (final e in expenses) e.id: e};
    final grouped = <String, List<Expense>>{};
    for (final link in links) {
      final e = byId[link.expenseId];
      if (e != null) grouped.putIfAbsent(link.tagId, () => []).add(e);
    }
    return [
      for (final entry in grouped.entries)
        if (signedSpend(entry.value) != 0) TagSlice(tagId: entry.key, amountCents: signedSpend(entry.value)),
    ];
  }

  /// A4.1 — signed spend per tag group (`tagGroupId → cents`).
  Future<Map<String, int>> byGroup(DateRange range, String currency) async {
    final (expenses, links) = await _expensesAndLinks(range, currency);
    final byId = {for (final e in expenses) e.id: e};
    final tags = await _db.select(_db.tags).get();
    final groupOf = {for (final t in tags) t.id: t.tagGroupId};

    final grouped = <String, List<Expense>>{};
    for (final link in links) {
      final e = byId[link.expenseId];
      final group = groupOf[link.tagId];
      if (e != null && group != null) grouped.putIfAbsent(group, () => []).add(e);
    }
    return {for (final entry in grouped.entries) entry.key: signedSpend(entry.value)};
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
    final (expenses, links) = await _expensesAndLinks(range, currency);
    final byId = {for (final e in expenses) e.id: e};
    final result = <String, Map<String?, int>>{};
    for (final link in links) {
      final e = byId[link.expenseId];
      if (e == null || (e.type != 'expense' && e.type != 'refund')) continue;
      final signed = e.type == 'refund' ? -e.amount : e.amount;
      final row = result.putIfAbsent(link.tagId, () => {});
      row[e.categoryId] = (row[e.categoryId] ?? 0) + signed;
    }
    return result;
  }
}

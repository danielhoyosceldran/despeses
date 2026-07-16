import '../../../data/database.dart';
import '../budget_repository.dart';
import 'analytics_math.dart';
import 'analytics_query.dart';

/// Central-tendency ticket stats for a period (A8.2).
class TicketStats {
  const TicketStats({required this.mean, required this.median, required this.max, required this.count});

  final double mean;
  final double median;
  final int max;
  final int count;
}

/// Refund summary for a period (A8.7).
class RefundSummary {
  const RefundSummary({required this.totalRefunded, required this.grossSpend});

  final int totalRefunded;
  final int grossSpend; // gross expense before refunds

  /// Refund as a fraction of gross spend (0 when there is no spend).
  double get ratio => grossSpend == 0 ? 0 : totalRefunded / grossSpend;
}

/// Transaction-behaviour analytics (Analytics › Comportamiento, section A8).
/// These describe consumption, so they operate on `expense` transactions
/// (refunds handled separately); income/savings are ignored.
class BehaviorAnalytics {
  BehaviorAnalytics(this._db);

  final AppDatabase _db;

  Future<List<Expense>> _spendTxns(DateRange range, String currency) async {
    final all = await expensesInRange(_db, range, currency);
    return all.where((e) => e.type == 'expense').toList();
  }

  /// A8.1 — number of expense transactions per month.
  Future<List<(DateTime, int)>> countByMonth(DateRange range, String currency) async {
    final txns = await _spendTxns(range, currency);
    final byMonth = <String, int>{};
    for (final e in txns) {
      byMonth[monthKeyOf(e.date)] = (byMonth[monthKeyOf(e.date)] ?? 0) + 1;
    }
    return [
      for (final m in monthsIn(range)) (m, byMonth[monthKeyOf(m)] ?? 0),
    ];
  }

  /// A8.2 — mean, median and max ticket over [range].
  Future<TicketStats> ticketStats(DateRange range, String currency) async {
    final amounts = (await _spendTxns(range, currency)).map((e) => e.amount).toList();
    return TicketStats(
      mean: mean(amounts),
      median: median(amounts),
      max: amounts.isEmpty ? 0 : amounts.reduce((a, b) => a > b ? a : b),
      count: amounts.length,
    );
  }

  /// A8.3 — histogram of ticket sizes into [bucketEdges] (upper bounds, cents).
  /// Returns a count per bucket; the final bucket catches everything above the
  /// last edge.
  Future<List<int>> histogram(DateRange range, String currency, List<int> bucketEdges) async {
    final amounts = (await _spendTxns(range, currency)).map((e) => e.amount);
    final counts = List<int>.filled(bucketEdges.length + 1, 0);
    for (final a in amounts) {
      var placed = false;
      for (var i = 0; i < bucketEdges.length; i++) {
        if (a <= bucketEdges[i]) {
          counts[i]++;
          placed = true;
          break;
        }
      }
      if (!placed) counts[bucketEdges.length]++;
    }
    return counts;
  }

  /// A8.4 — the [n] largest expense transactions of the period.
  Future<List<Expense>> topTransactions(DateRange range, String currency, {int n = 5}) async {
    final txns = await _spendTxns(range, currency)..sort((a, b) => b.amount.compareTo(a.amount));
    return txns.take(n).toList();
  }

  /// A8.5 — "ant spend": total of micro-transactions below [thresholdCents].
  Future<({int total, int count})> antSpend(DateRange range, String currency, int thresholdCents) async {
    final small = (await _spendTxns(range, currency)).where((e) => e.amount < thresholdCents);
    return (total: small.fold<int>(0, (s, e) => s + e.amount), count: small.length);
  }

  /// A8.6 — for a month: the set of days with no spend and the current run of
  /// consecutive no-spend days ending at the last day of the month (or today).
  Future<({int noSpendDays, int currentStreak})> noSpendDays(
    DateTime month,
    String currency, {
    DateTime? asOf,
  }) async {
    final txns = await _spendTxns(DateRange.month(month), currency);
    final spentDays = txns.map((e) => e.date.day).toSet();
    final now = asOf ?? DateTime.now();
    final lastDay = (now.year == month.year && now.month == month.month)
        ? now.day
        : DateTime(month.year, month.month + 1, 0).day;

    var noSpend = 0;
    for (var d = 1; d <= lastDay; d++) {
      if (!spentDays.contains(d)) noSpend++;
    }
    var streak = 0;
    for (var d = lastDay; d >= 1; d--) {
      if (spentDays.contains(d)) break;
      streak++;
    }
    return (noSpendDays: noSpend, currentStreak: streak);
  }

  /// A8.7 — refunds vs gross spend for the period.
  Future<RefundSummary> refunds(DateRange range, String currency) async {
    final all = await expensesInRange(_db, range, currency);
    return RefundSummary(
      totalRefunded: sumOfType(all, 'refund'),
      grossSpend: sumOfType(all, 'expense'),
    );
  }
}

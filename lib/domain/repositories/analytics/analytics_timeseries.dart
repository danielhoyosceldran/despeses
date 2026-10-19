import '../../../data/database.dart';
import 'analytics_math.dart';
import 'analytics_query.dart';

/// Month-over-month / year-over-year comparison (A1.3), in absolute cents and
/// as a fraction (`null` when the baseline is zero, i.e. no meaningful %).
class Comparison {
  const Comparison({required this.current, required this.previous});

  final int current;
  final int previous;

  int get absolute => current - previous;
  double? get fraction => previous == 0 ? null : (current - previous) / previous;
}

/// Time-series spend analytics (Analytics › Tendencia, section A1). "Spend" here
/// is pure expense outflow (expense − refund; income and savings excluded).
class TimeseriesAnalytics {
  TimeseriesAnalytics(this._db);

  final AppDatabase _db;

  /// A1.1 — signed spend per month across [range].
  Future<List<(DateTime, int)>> monthlyTotals(DateRange range, String currency) async {
    final months = monthsIn(range);
    final groups = await aggregateInRange(_db, range, currency, buckets: months, types: spendTypes);
    return spentPerBucket(months, groups);
  }

  /// Spent per bucket of [groups] (aggregated with [starts] as buckets).
  static List<(DateTime, int)> spentPerBucket(List<DateTime> starts, Iterable<AmountGroup> groups) {
    final totals = List<int>.filled(starts.length, 0);
    for (final g in groups) {
      totals[g.bucket] += spentContribution(g.type, g.total);
    }
    return [for (var i = 0; i < starts.length; i++) (starts[i], totals[i])];
  }

  /// A1.2 — trailing moving average of the monthly totals over [window] months.
  Future<List<(DateTime, double)>> movingAverage(
    DateRange range,
    String currency, {
    int window = 3,
  }) async {
    final totals = await monthlyTotals(range, currency);
    return [
      for (var i = 0; i < totals.length; i++)
        () {
          final start = (i - window + 1).clamp(0, totals.length);
          final slice = totals.sublist(start, i + 1).map((e) => e.$2);
          return (totals[i].$1, mean(slice));
        }(),
    ];
  }

  /// A1.3 — this month vs previous month, and vs the same month last year.
  Future<({Comparison mom, Comparison yoy})> momYoY(DateTime month, String currency) async {
    Future<int> spendOf(DateTime m) async =>
        (await aggregateInRange(_db, DateRange.month(m), currency, types: spendTypes)).spent;

    final current = await spendOf(month);
    final prevMonth = await spendOf(DateTime(month.year, month.month - 1, 1));
    final prevYear = await spendOf(DateTime(month.year - 1, month.month, 1));
    return (
      mom: Comparison(current: current, previous: prevMonth),
      yoy: Comparison(current: current, previous: prevYear),
    );
  }

  /// A1.6 — average daily spend per weekday (Mon..Sun → indices 1..7 of the
  /// returned map) across [range].
  Future<Map<int, double>> averageByWeekday(DateRange range, String currency) async {
    final expenses = await expensesInRange(_db, range, currency, types: spendTypes);
    final sums = <int, int>{};
    final days = <int, Set<String>>{};
    for (final e in expenses) {
      if (e.type != 'expense' && e.type != 'refund') continue;
      final wd = e.date.weekday; // 1=Mon..7=Sun
      final signed = signedAmountOf(e);
      sums[wd] = (sums[wd] ?? 0) + signed;
      days.putIfAbsent(wd, () => {}).add('${e.date.year}-${e.date.month}-${e.date.day}');
    }
    return {
      for (var wd = 1; wd <= 7; wd++)
        wd: (days[wd]?.isEmpty ?? true) ? 0.0 : (sums[wd] ?? 0) / days[wd]!.length,
    };
  }

  /// A1.7 — spend per calendar day of [month] (day-of-month → signed cents).
  Future<Map<int, int>> calendarHeat(DateTime month, String currency) async {
    final groups = await aggregateInRange(
      _db,
      DateRange.month(month),
      currency,
      buckets: daysOf(month),
      types: spendTypes,
    );
    final byDay = <int, int>{};
    for (final g in groups) {
      final day = g.bucket + 1;
      byDay[day] = (byDay[day] ?? 0) + spentContribution(g.type, g.total);
    }
    return byDay;
  }

  /// A1.4 — cumulative spend day-by-day for [month] and for the previous month
  /// (burn-up). Each list is (dayOfMonth, cumulativeCents).
  Future<({List<(int, int)> current, List<(int, int)> previous})> burnUp(
    DateTime month,
    String currency,
  ) async {
    Future<List<(int, int)>> cumulative(DateTime m) async {
      final heat = await calendarHeat(m, currency);
      final lastDay = DateTime(m.year, m.month + 1, 0).day;
      var acc = 0;
      return [
        for (var d = 1; d <= lastDay; d++) (d, acc += (heat[d] ?? 0)),
      ];
    }

    return (
      current: await cumulative(month),
      previous: await cumulative(DateTime(month.year, month.month - 1, 1)),
    );
  }

  /// A1.5 — end-of-month projection: extrapolate the current daily pace to the
  /// full month. When [asOf] is omitted, today is used.
  Future<int> endOfMonthProjection(DateTime month, String currency, {DateTime? asOf}) async {
    final spentSoFar =
        (await aggregateInRange(_db, DateRange.month(month), currency, types: spendTypes)).spent;
    return projectEndOfMonth(spentSoFar, month, asOf: asOf);
  }

  /// [endOfMonthProjection] from an already computed [spentSoFar].
  static int projectEndOfMonth(int spentSoFar, DateTime month, {DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final dayCursor = (now.year == month.year && now.month == month.month) ? now.day : lastDay;
    if (dayCursor <= 0) return spentSoFar;
    final pace = spentSoFar / dayCursor;
    return (pace * lastDay).round();
  }
}

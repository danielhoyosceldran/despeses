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
/// is the signed total (expense − refund; income and savings excluded).
class TimeseriesAnalytics {
  TimeseriesAnalytics(this._db);

  final AppDatabase _db;

  /// A1.1 — signed spend per month across [range].
  Future<List<(DateTime, int)>> monthlyTotals(DateRange range, String currency) async {
    final expenses = await expensesInRange(_db, range, currency);
    final byMonth = <String, List<Expense>>{};
    for (final e in expenses) {
      byMonth.putIfAbsent('${e.date.year}-${e.date.month}', () => []).add(e);
    }
    return [
      for (final m in monthsIn(range))
        (m, signedSpend(byMonth['${m.year}-${m.month}'] ?? const [])),
    ];
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
    Future<int> spendOf(DateTime m) async {
      final list = await expensesInRange(_db, DateRange.month(m), currency);
      return signedSpend(list);
    }

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
    final expenses = await expensesInRange(_db, range, currency);
    final sums = <int, int>{};
    final days = <int, Set<String>>{};
    for (final e in expenses) {
      if (e.type != 'expense' && e.type != 'refund') continue;
      final wd = e.date.weekday; // 1=Mon..7=Sun
      final signed = e.type == 'refund' ? -e.amount : e.amount;
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
    final expenses = await expensesInRange(_db, DateRange.month(month), currency);
    final byDay = <int, int>{};
    for (final e in expenses) {
      if (e.type != 'expense' && e.type != 'refund') continue;
      final signed = e.type == 'refund' ? -e.amount : e.amount;
      byDay[e.date.day] = (byDay[e.date.day] ?? 0) + signed;
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
    final now = asOf ?? DateTime.now();
    final spentSoFar = signedSpend(await expensesInRange(_db, DateRange.month(month), currency));
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final dayCursor = (now.year == month.year && now.month == month.month) ? now.day : lastDay;
    if (dayCursor <= 0) return spentSoFar;
    final pace = spentSoFar / dayCursor;
    return (pace * lastDay).round();
  }
}

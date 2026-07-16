import '../../../data/database.dart';
import '../budget_repository.dart';
import 'analytics_math.dart';
import 'analytics_query.dart';

/// One month of cash-flow: gross income, net spend (expense − refund) and money
/// set aside (`ahorro`). Disposable cash = income − spend − savings.
class MonthlyCashflow {
  const MonthlyCashflow({
    required this.month,
    required this.income,
    required this.spend,
    required this.savings,
  });

  final DateTime month;
  final int income;
  final int spend;
  final int savings;

  /// Net cash-flow for the month: what stays after spending and setting aside.
  int get net => income - spend - savings;

  /// Fraction of income kept as savings (0 when there is no income). This is the
  /// "savings rate" (A2.2): real recorded savings over income.
  double get savingsRate => income == 0 ? 0 : savings / income;
}

/// Income vs spend vs savings over time (Analytics › Flujo de caja, section A2).
class CashflowAnalytics {
  CashflowAnalytics(this._db);

  final AppDatabase _db;

  /// Per-month cash-flow across [range].
  Future<List<MonthlyCashflow>> monthly(DateRange range, String currency) async {
    final expenses = await expensesInRange(_db, range, currency);
    final byMonth = <String, List<Expense>>{};
    for (final e in expenses) {
      final key = monthKeyOf(e.date);
      byMonth.putIfAbsent(key, () => []).add(e);
    }
    return [
      for (final month in monthsIn(range))
        () {
          final group = byMonth[monthKeyOf(month)] ?? const [];
          return MonthlyCashflow(
            month: month,
            income: sumOfType(group, 'income'),
            spend: signedSpend(group),
            savings: sumOfType(group, 'ahorro'),
          );
        }(),
    ];
  }

  /// A2.2 — savings rate for a single month (real savings / income).
  Future<double> savingsRate(DateTime month, String currency) async {
    final rows = await monthly(DateRange.month(month), currency);
    return rows.isEmpty ? 0 : rows.first.savingsRate;
  }

  /// A2.3 — running balance (cumulative net cash-flow) across [range].
  Future<List<(DateTime, int)>> cumulativeBalance(DateRange range, String currency) async {
    final rows = await monthly(range, currency);
    var acc = 0;
    return [
      for (final r in rows) (r.month, acc += r.net),
    ];
  }

  /// Cumulative savings (running total of `ahorro`) across [range] — the
  /// "ahorro acumulado" view.
  Future<List<(DateTime, int)>> cumulativeSavings(DateRange range, String currency) async {
    final rows = await monthly(range, currency);
    var acc = 0;
    return [
      for (final r in rows) (r.month, acc += r.savings),
    ];
  }
}

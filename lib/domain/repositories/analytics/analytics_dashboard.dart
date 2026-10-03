import '../../../data/database.dart';
import '../budget_repository.dart';
import 'analytics_behavior.dart';
import 'analytics_budgets.dart';
import 'analytics_cashflow.dart';
import 'analytics_category.dart';
import 'analytics_math.dart';
import 'analytics_query.dart';
import 'analytics_timeseries.dart';

/// The financial-health KPIs shown at the top of Analytics (A10.1).
class FinancialHealth {
  const FinancialHealth({
    required this.savingsRate,
    required this.spendThisMonth,
    required this.averageSpend3M,
    required this.topCategoryId,
    required this.topCategoryCents,
    required this.projectedSpend,
    required this.noSpendStreak,
    required this.budgetsAtRisk,
  });

  final double savingsRate;
  final int spendThisMonth;
  final double averageSpend3M;
  final String? topCategoryId;
  final int topCategoryCents;
  final int projectedSpend;
  final int noSpendStreak;
  final int budgetsAtRisk;

  /// Spend vs the 3-month average, as a fraction (null when no history).
  double? get spendVsAverage =>
      averageSpend3M == 0 ? null : (spendThisMonth - averageSpend3M) / averageSpend3M;
}

/// Composes the section calculators into the health dashboard (A10.1).
class DashboardAnalytics {
  DashboardAnalytics(this._db, this._category, this._budgetAnalytics, this._budgets);

  final AppDatabase _db;
  final CategoryAnalytics _category;
  final BudgetAnalytics _budgetAnalytics;
  final BudgetRepository _budgets;

  /// Every KPI is derived from one shared snapshot of the period (BL-062)
  /// instead of each metric re-querying the same month: one aggregate of the
  /// trailing 3 months per month × type × category, one per-day aggregate of
  /// [month] for the streak, and one batch for every budget.
  Future<FinancialHealth> summary(DateTime month, String currency, {DateTime? asOf}) async {
    final months = monthsIn(DateRange.trailingMonths(month, 3));
    final groups = await aggregateInRange(
      _db,
      DateRange.trailingMonths(month, 3),
      currency,
      buckets: months,
      groupBy: const {AggregateBy.category},
    );
    final current = groups.where((g) => g.bucket == months.length - 1).toList();

    final trailing = TimeseriesAnalytics.spentPerBucket(months, groups.where((g) => spendTypes.contains(g.type)));
    final spendThisMonth = trailing.last.$2;
    final avg3M = mean(trailing.map((e) => e.$2));

    final ranking = await _category.rankingFrom(
      CategoryAnalytics.totalsByCategory(current.where((g) => g.type == 'expense')),
      type: 'expense',
    );
    final top = ranking.isEmpty ? null : ranking.first;

    final dailyExpenses = await aggregateInRange(
      _db,
      DateRange.month(month),
      currency,
      buckets: daysOf(month),
      types: const ['expense'],
    );
    final streak = BehaviorAnalytics.noSpendFrom(
      {for (final g in dailyExpenses) g.bucket + 1},
      month,
      asOf: asOf,
    ).currentStreak;
    final projection = TimeseriesAnalytics.projectEndOfMonth(spendThisMonth, month, asOf: asOf);
    final savingsRate = MonthlyCashflow(
      month: months.last,
      income: current.ofType('income'),
      spend: current.spent,
      savings: current.savings,
    ).savingsRate;

    final monthKey = monthKeyOf(DateTime(month.year, month.month));
    final active = (await _budgets.listAll()).where((b) => _budgets.isActiveForMonth(b, monthKey)).toList();
    // "At risk" must be evaluated inside the *displayed* month, not always the
    // current one (R33). The pace takes a single `asOf` that drives both the
    // spend window and the elapsed-time fraction, so anchor it to `month`:
    //  - past month  → end of that month: time fraction 1, i.e. plain
    //                  spent-vs-limit for a period that is fully over;
    //  - current month → today (unchanged behaviour);
    //  - future month → nothing has been spent or elapsed yet, so no risk.
    final now = asOf ?? DateTime.now();
    final currentMonthKey = monthKeyOf(DateTime(now.year, now.month));
    final comparison = monthKey.compareTo(currentMonthKey);
    var atRisk = 0;
    if (comparison <= 0 && active.isNotEmpty) {
      // Last day of `month` for a past month, `now` for the current one.
      final paceAsOf = comparison < 0 ? DateTime(month.year, month.month + 1, 0) : now;
      final progress = await _budgets.progressFor(active, inMonth: paceAsOf);
      for (final b in active) {
        final pace = _budgetAnalytics.paceOf(b, progress[b.id] ?? 0, asOf: paceAsOf);
        if (pace.overPace || pace.spentFraction > 1) atRisk++;
      }
    }

    return FinancialHealth(
      savingsRate: savingsRate,
      spendThisMonth: spendThisMonth,
      averageSpend3M: avg3M,
      topCategoryId: top?.categoryId,
      topCategoryCents: top?.amountCents ?? 0,
      projectedSpend: projection,
      noSpendStreak: streak,
      budgetsAtRisk: atRisk,
    );
  }
}

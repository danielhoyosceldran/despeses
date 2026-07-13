import '../budget_repository.dart';
import 'analytics_behavior.dart';
import 'analytics_budgets.dart';
import 'analytics_cashflow.dart';
import 'analytics_category.dart';
import 'analytics_math.dart';
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
  DashboardAnalytics(
    this._cashflow,
    this._timeseries,
    this._category,
    this._behavior,
    this._budgetAnalytics,
    this._budgets,
  );

  final CashflowAnalytics _cashflow;
  final TimeseriesAnalytics _timeseries;
  final CategoryAnalytics _category;
  final BehaviorAnalytics _behavior;
  final BudgetAnalytics _budgetAnalytics;
  final BudgetRepository _budgets;

  Future<FinancialHealth> summary(DateTime month, String currency, {DateTime? asOf}) async {
    final trailing = await _timeseries.monthlyTotals(DateRange.trailingMonths(month, 3), currency);
    final spendThisMonth = trailing.isEmpty ? 0 : trailing.last.$2;
    final avg3M = mean(trailing.map((e) => e.$2));

    final ranking = await _category.ranking(DateRange.month(month), type: 'expense', currency: currency);
    final top = ranking.isEmpty ? null : ranking.first;

    final streak = (await _behavior.noSpendDays(month, currency, asOf: asOf)).currentStreak;
    final projection = await _timeseries.endOfMonthProjection(month, currency, asOf: asOf);
    final savingsRate = await _cashflow.savingsRate(month, currency);

    final monthKey = monthKeyOf(DateTime(month.year, month.month));
    final active = (await _budgets.listAll()).where((b) => _budgets.isActiveForMonth(b, monthKey));
    var atRisk = 0;
    for (final b in active) {
      final pace = await _budgetAnalytics.pace(b, asOf: asOf);
      if (pace.overPace || pace.spentFraction > 1) atRisk++;
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

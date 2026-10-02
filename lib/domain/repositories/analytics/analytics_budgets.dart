import '../../../data/database.dart';
import '../budget_repository.dart';

/// Pace + projection for one budget (A7.1–A7.3).
class BudgetPace {
  const BudgetPace({
    required this.spentCents,
    required this.limitCents,
    required this.timeFraction,
  });

  final int spentCents;
  final int limitCents;

  /// Elapsed fraction of the budget period (0..1). For `monthly` budgets this
  /// is how far through the current month we are; for `range` budgets, elapsed
  /// days over the total days of the window (both day-level, today counted as
  /// elapsed).
  final double? timeFraction;

  double get spentFraction => limitCents == 0 ? 0 : spentCents / limitCents;

  /// True when spending outpaces time (spent% ahead of elapsed%).
  bool get overPace => timeFraction != null && timeFraction! > 0 && spentFraction > timeFraction!;

  /// A7.3 — projected end-of-period spend at the current pace (null when it
  /// cannot be projected: no time bound or nothing elapsed yet).
  int? get projectedEndCents {
    if (timeFraction == null || timeFraction! <= 0) return null;
    return (spentCents / timeFraction!).round();
  }
}

/// Budget analytics (Analytics › Presupuestos, section A7). Reuses
/// [BudgetRepository.calculateProgress] for the spent figure and adds pacing,
/// projection and historical compliance on top.
class BudgetAnalytics {
  BudgetAnalytics(this._budgets);

  final BudgetRepository _budgets;

  /// Elapsed fraction (0..1) of a budget's configured period as of [asOf].
  double? _timeFraction(Budget budget, DateTime asOf) {
    switch (budget.budgetType) {
      case 'monthly':
        // Fraction of the current month elapsed (day-level).
        final daysInMonth = DateTime(asOf.year, asOf.month + 1, 0).day;
        return asOf.day / daysInMonth;
      case 'range':
        // Day-level over [first day of startsMonth, last day of endsMonth].
        // UTC dates so a DST change can't make a day 23h and skew inDays.
        final s = budget.startsMonth!.split('-');
        final e = budget.endsMonth!.split('-');
        final start = DateTime.utc(int.parse(s[0]), int.parse(s[1]));
        final endExclusive = DateTime.utc(int.parse(e[0]), int.parse(e[1]) + 1);
        final total = endExclusive.difference(start).inDays;
        if (total <= 0) return null;
        final today = DateTime.utc(asOf.year, asOf.month, asOf.day);
        final elapsed = (today.difference(start).inDays + 1).clamp(0, total);
        return elapsed / total;
      default:
        return null;
    }
  }

  /// A7.1–A7.3 — spent, limit, elapsed time fraction, over-pace flag, projection.
  Future<BudgetPace> pace(Budget budget, {DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final spent = await _budgets.calculateProgress(budget, inMonth: now);
    final timeFraction = _timeFraction(budget, now);
    return BudgetPace(spentCents: spent, limitCents: budget.amount, timeFraction: timeFraction);
  }

  /// A7.4 — historical compliance across budgets whose period has fully ended
  /// before [asOf]: how many were met (spent ≤ limit) and the mean overspend
  /// fraction (over the limit) among those exceeded.
  Future<({int met, int exceeded, double meanOverspend})> history(
    List<Budget> budgets, {
    DateTime? asOf,
  }) async {
    final now = asOf ?? DateTime.now();
    final asOfKey = monthKeyOf(DateTime(now.year, now.month));
    var met = 0;
    var exceeded = 0;
    final overspends = <double>[];
    for (final b in budgets) {
      final ended = switch (b.budgetType) {
        'range' => b.endsMonth!.compareTo(asOfKey) < 0,
        _ => false, // monthly budgets recur forever, never "end"
      };
      if (!ended) continue;
      final spent = await _budgets.calculateProgress(b);
      if (spent <= b.amount) {
        met++;
      } else {
        exceeded++;
        if (b.amount > 0) overspends.add((spent - b.amount) / b.amount);
      }
    }
    final meanOverspend = overspends.isEmpty ? 0.0 : overspends.reduce((a, c) => a + c) / overspends.length;
    return (met: met, exceeded: exceeded, meanOverspend: meanOverspend);
  }
}

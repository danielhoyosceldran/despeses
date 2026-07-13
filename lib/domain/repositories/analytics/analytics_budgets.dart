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

  /// Elapsed fraction of the budget period (0..1), or null for `total` budgets
  /// which have no time bound.
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

  /// (elapsedMonths, totalMonths) of a budget's configured period as of [asOf].
  (int, int)? _periodMonths(Budget budget, DateTime asOf) {
    final asOfKey = monthKeyOf(DateTime(asOf.year, asOf.month));
    switch (budget.budgetType) {
      case 'range':
        final start = budget.startsMonth!;
        final end = budget.endsMonth;
        int monthsBetween(String a, String b) {
          final pa = a.split('-');
          final pb = b.split('-');
          return (int.parse(pb[0]) - int.parse(pa[0])) * 12 + (int.parse(pb[1]) - int.parse(pa[1]));
        }

        if (end == null) return null; // open-ended range: no total
        final total = monthsBetween(start, end) + 1;
        final elapsedTo = asOfKey.compareTo(end) > 0 ? end : (asOfKey.compareTo(start) < 0 ? start : asOfKey);
        final elapsed = (monthsBetween(start, elapsedTo) + 1).clamp(0, total);
        return (elapsed, total);
      case 'months':
        final months = _budgets.decodeMonths(budget);
        if (months.isEmpty) return null;
        final total = months.length;
        final elapsed = months.where((m) => m.key.compareTo(asOfKey) <= 0).length;
        return (elapsed, total);
      case 'total':
      default:
        return null;
    }
  }

  /// A7.1–A7.3 — spent, limit, elapsed time fraction, over-pace flag, projection.
  Future<BudgetPace> pace(Budget budget, {DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final spent = await _budgets.calculateProgress(budget);
    final period = _periodMonths(budget, now);
    final timeFraction = period == null || period.$2 == 0 ? null : period.$1 / period.$2;
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
        'range' => b.endsMonth != null && b.endsMonth!.compareTo(asOfKey) < 0,
        'months' => _budgets.decodeMonths(b).every((m) => m.key.compareTo(asOfKey) < 0) &&
            _budgets.decodeMonths(b).isNotEmpty,
        _ => false, // total budgets never "end"
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

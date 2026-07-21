import '../../../data/database.dart';

/// Inclusive date range `[from, to]` used by every time-scoped analytics query.
class DateRange {
  const DateRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  /// The single calendar month containing [month] (first day 00:00 → last day 23:59:59).
  factory DateRange.month(DateTime month) {
    final from = DateTime(month.year, month.month, 1);
    final to = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    return DateRange(from, to);
  }

  /// A rolling window of [count] whole months ending with (and including) the
  /// month of [anchor]. E.g. count 12 → the last 12 months.
  factory DateRange.trailingMonths(DateTime anchor, int count) {
    final start = DateTime(anchor.year, anchor.month - (count - 1), 1);
    final end = DateTime(anchor.year, anchor.month + 1, 0, 23, 59, 59);
    return DateRange(start, end);
  }
}

/// First-of-month markers for each calendar month within [range] (inclusive).
List<DateTime> monthsIn(DateRange range) {
  final months = <DateTime>[];
  var cursor = DateTime(range.from.year, range.from.month, 1);
  final last = DateTime(range.to.year, range.to.month, 1);
  while (!cursor.isAfter(last)) {
    months.add(cursor);
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }
  return months;
}

/// The signed **spend** total: `expense` and `ahorro` add, `refund`
/// subtracts, `income` is excluded.
int signedSpend(Iterable<Expense> expenses) {
  var total = 0;
  for (final e in expenses) {
    switch (e.type) {
      case 'expense':
      case 'ahorro':
        total += e.amount;
      case 'refund':
        total -= e.amount;
      // income excluded.
    }
  }
  return total;
}

/// Signed amount of a single spend transaction: `expense` positive, `refund`
/// negative. Only meaningful for lists already filtered to expense/refund.
int signedAmountOf(Expense e) => e.type == 'refund' ? -e.amount : e.amount;

/// Plain sum of the (always-positive) amounts of a single transaction [type].
int sumOfType(Iterable<Expense> expenses, String type) {
  var total = 0;
  for (final e in expenses) {
    if (e.type == type) total += e.amount;
  }
  return total;
}

double mean(Iterable<int> values) {
  final list = values.toList();
  if (list.isEmpty) return 0;
  return list.reduce((a, b) => a + b) / list.length;
}

/// Median of [values] (0 when empty). For an even count, the average of the two
/// central values.
double median(Iterable<int> values) {
  final list = values.toList()..sort();
  if (list.isEmpty) return 0;
  final mid = list.length ~/ 2;
  if (list.length.isOdd) return list[mid].toDouble();
  return (list[mid - 1] + list[mid]) / 2;
}

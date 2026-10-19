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

// Spend vs. savings — the single definition every screen uses:
//
// - **Spent** ("Gastado") = [expenseOutflow]: `expense` minus `refund`.
// - **Savings** ("Ahorro") = [savingsSetAside]: money set aside as not
//   available this month. It is NOT spending and is shown as its own figure.
// - **Balance** = income − spent − savings: savings still reduce what's left.

/// Start of tomorrow. Transactions dated on or after it are **scheduled**:
/// recorded ahead of time, they don't count anywhere (totals, analytics,
/// projection, streaks, budgets, goals) until their day arrives; lists show
/// them marked as scheduled. [now] is injectable for tests.
DateTime scheduledFrom([DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateTime(n.year, n.month, n.day + 1);
}

/// Whether [e] is scheduled (dated after today); see [scheduledFrom].
bool isScheduled(Expense e, {DateTime? now}) => !e.date.isBefore(scheduledFrom(now));

/// Spent: `expense` positive, `refund` subtracts; `ahorro` and `income`
/// excluded. Use this wherever a figure means "spent" (see the note above).
int expenseOutflow(Iterable<Expense> expenses) {
  var total = 0;
  for (final e in expenses) {
    total += spentContribution(e.type, e.amount);
  }
  return total;
}

/// What [amount] of a transaction [type] adds to the spent figure: `expense`
/// positive, `refund` negative, `ahorro`/`income` nothing. The single rule
/// behind [expenseOutflow] and the SQL aggregates (`AmountGroups.spent`).
int spentContribution(String type, int amount) => switch (type) {
      'expense' => amount,
      'refund' => -amount,
      _ => 0,
    };

/// Transaction types that make up the spent figure.
const spendTypes = ['expense', 'refund'];

/// Savings set aside: the sum of `ahorro` amounts. Shown next to (never inside)
/// the spent figure.
int savingsSetAside(Iterable<Expense> expenses) => sumOfType(expenses, 'ahorro');

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

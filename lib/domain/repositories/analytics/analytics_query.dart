import 'package:drift/drift.dart';

import '../../../data/database.dart';
import 'analytics_math.dart';

/// Shared expense fetch: everything in [range] for the profile [currency].
/// Multi-currency consolidation is out of scope, so callers pass the single
/// profile currency and other-currency rows are ignored.
Future<List<Expense>> expensesInRange(
  AppDatabase db,
  DateRange range,
  String currency,
) {
  return (db.select(db.expenses)
        ..where((e) => e.currency.equals(currency))
        ..where((e) => e.date.isBiggerOrEqualValue(range.from))
        ..where((e) => e.date.isSmallerOrEqualValue(range.to)))
      .get();
}

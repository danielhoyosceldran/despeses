import 'package:drift/drift.dart';

/// SQL type of the accounting dates (BL-042): the transaction date, recurring
/// schedule dates, occurrence due dates, event/project spans and goal
/// deadlines.
///
/// Drift's built-in `dateTime()` stores an instant (unix seconds) and reads it
/// back in the device's current time zone, so a row saved at 00:30 in Madrid
/// shows up on the previous day (and maybe month) when the phone is in London.
/// An accounting date is a civil date/time instead: "3 Oct 2026, 00:30",
/// whatever the zone. This type stores the *wall-clock components* encoded as
/// if they were UTC (`DateTime.utc(y, m, d, h, min, s)` in unix seconds) and
/// reads them back as a local [DateTime] with the same components. The rest of
/// the app keeps working with plain local DateTimes.
///
/// Still an INTEGER column ordered like time, so range filters, the indexes
/// and the keyset pagination keep working. Comparisons against Dart values go
/// through this type too (drift binds `isBiggerOrEqualValue` & co. with the
/// column's type); raw SQL must bind with [civilVariable].
///
/// Instants (`created_at`, `updated_at`, `last_posted_at`) keep drift's
/// built-in mapping.
class CivilDateTimeType implements CustomSqlType<DateTime> {
  const CivilDateTimeType();

  /// Unix seconds of [value]'s local wall-clock components taken as UTC.
  static int encode(DateTime value) {
    final d = value.isUtc ? value.toLocal() : value;
    return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second).millisecondsSinceEpoch ~/ 1000;
  }

  /// Local [DateTime] with the wall-clock components stored by [encode].
  static DateTime decode(int seconds) {
    final u = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
  }

  @override
  String mapToSqlLiteral(DateTime dartValue) => '${encode(dartValue)}';

  @override
  Object mapToSqlParameter(DateTime dartValue) => encode(dartValue);

  @override
  DateTime read(Object fromSql) => decode(fromSql is int ? fromSql : (fromSql as num).toInt());

  @override
  String sqlTypeName(GenerationContext context) => 'INTEGER';
}

const civilDateTimeType = CivilDateTimeType();

/// Bind variable for an accounting-date column in raw SQL (`customSelect`).
Variable<DateTime> civilVariable(DateTime value) => Variable<DateTime>(value, civilDateTimeType);

import 'package:drift/drift.dart';

import '../../../data/database.dart';
import 'analytics_math.dart';

/// Shared expense fetch: everything in [range] for the profile [currency].
/// Multi-currency consolidation is out of scope, so callers pass the single
/// profile currency and other-currency rows are ignored. [types] restricts the
/// rows to those transaction types in SQL.
///
/// Prefer [aggregateExpenses] whenever only totals/counts are needed: this
/// loads full rows and is meant for lists and per-row statistics.
Future<List<Expense>> expensesInRange(
  AppDatabase db,
  DateRange range,
  String currency, {
  Iterable<String>? types,
}) {
  final query = db.select(db.expenses)
    ..where((e) => e.currency.equals(currency))
    ..where((e) => e.date.isBiggerOrEqualValue(range.from))
    ..where((e) => e.date.isSmallerOrEqualValue(range.to))
    // Scheduled (future-dated) rows don't count until their day.
    ..where((e) => e.date.isSmallerThanValue(scheduledFrom()));
  if (types != null) query.where((e) => e.type.isIn(types));
  return query.get();
}

/// Dimensions an aggregate can be grouped by (on top of bucket and type,
/// which every aggregate groups by).
enum AggregateBy { category, project, event, tag }

/// One aggregated group of counted transactions: the [total] amount and
/// [count] of the rows of one [type] falling in time bucket [bucket] (index
/// into the `buckets` passed to [aggregateExpenses]; 0 when ungrouped) and in
/// the requested dimensions (null when not grouped by it, or unset on the row).
class AmountGroup {
  const AmountGroup({
    required this.bucket,
    required this.type,
    required this.total,
    required this.count,
    this.categoryId,
    this.projectId,
    this.eventId,
    this.tagId,
  });

  final int bucket;
  final String type;
  final int total;
  final int count;
  final String? categoryId;
  final String? projectId;
  final String? eventId;
  final String? tagId;
}

/// Totals over aggregated groups, with the same definitions as the row-based
/// helpers in `analytics_math.dart`.
extension AmountGroups on Iterable<AmountGroup> {
  /// Spent ([expenseOutflow]): expense − refund.
  int get spent => fold(0, (sum, g) => sum + spentContribution(g.type, g.total));

  /// Savings set aside ([savingsSetAside]).
  int get savings => ofType('ahorro');

  /// Plain sum of the amounts of one transaction [type] ([sumOfType]).
  int ofType(String type) => fold(0, (sum, g) => g.type == type ? sum + g.total : sum);

  /// Number of transactions aggregated.
  int get count => fold(0, (sum, g) => sum + g.count);
}

/// [aggregateExpenses] over an inclusive [DateRange], the shape every analytics
/// calculator uses.
Future<List<AmountGroup>> aggregateInRange(
  AppDatabase db,
  DateRange range,
  String currency, {
  List<DateTime>? buckets,
  Set<AggregateBy> groupBy = const {},
  Iterable<String>? types,
}) {
  return aggregateExpenses(
    db,
    currency: currency,
    from: range.from,
    to: range.to,
    buckets: buckets,
    groupBy: groupBy,
    types: types,
  );
}

/// Sums and counts the counted transactions in SQL (`SUM`/`COUNT` + `GROUP
/// BY`) instead of loading every row into Dart (BL-062). Rows are those of
/// [currency] dated in `[from, to]` (or `[from, before)` when [before] is
/// given instead of [to]), never scheduled ones, optionally restricted to
/// [types] and, for [AggregateBy.tag], to [tagIds].
///
/// Every result is grouped by transaction type, plus:
/// - [buckets]: ascending start instants; a row goes to the last bucket whose
///   start is ≤ its date (so the first should be ≤ [from]). Lets one query
///   return per-month or per-day figures with local-time boundaries computed
///   in Dart, so they match `DateTime(year, month, day)` exactly.
/// - [groupBy]: the extra dimensions. Grouping by [AggregateBy.tag] joins
///   `expense_tags`, so untagged rows drop out and a row with several tags
///   counts once per tag.
Future<List<AmountGroup>> aggregateExpenses(
  AppDatabase db, {
  required String currency,
  required DateTime from,
  DateTime? to,
  DateTime? before,
  List<DateTime>? buckets,
  Set<AggregateBy> groupBy = const {},
  Iterable<String>? types,
  Iterable<String>? tagIds,
}) async {
  assert((to == null) != (before == null), 'Pass exactly one of to/before.');
  final variables = <Variable>[];

  // Bucket index as a CASE over the bucket boundaries. Its variables come
  // first because the SELECT list precedes the WHERE clause.
  final starts = buckets ?? const <DateTime>[];
  String bucketSql = '0';
  if (starts.length > 1) {
    final sql = StringBuffer('CASE');
    for (var i = 1; i < starts.length; i++) {
      sql.write(' WHEN e.date < ? THEN ${i - 1}');
      variables.add(civilVariable(starts[i]));
    }
    sql.write(' ELSE ${starts.length - 1} END');
    bucketSql = sql.toString();
  }

  final byTag = groupBy.contains(AggregateBy.tag);
  String column(AggregateBy key, String sql) => groupBy.contains(key) ? sql : 'NULL';
  final where = <String>['e.currency = ?', 'e.date >= ?', 'e.date < ?'];
  variables
    ..add(Variable<String>(currency))
    ..add(civilVariable(from))
    // Scheduled (future-dated) rows don't count until their day.
    ..add(civilVariable(scheduledFrom()));
  if (to != null) {
    where.add('e.date <= ?');
    variables.add(civilVariable(to));
  } else {
    where.add('e.date < ?');
    variables.add(civilVariable(before!));
  }
  void addIn(String column, Iterable<String> values) {
    final list = values.toList();
    where.add('$column IN (${List.filled(list.length, '?').join(', ')})');
    variables.addAll(list.map(Variable<String>.new));
  }

  if (types != null) addIn('e.type', types);
  if (byTag && tagIds != null) addIn('et.tag_id', tagIds);

  final dimensions = [
    if (groupBy.contains(AggregateBy.category)) 'e.category_id',
    if (groupBy.contains(AggregateBy.project)) 'e.project_id',
    if (groupBy.contains(AggregateBy.event)) 'e.event_id',
    if (byTag) 'et.tag_id',
  ];
  final rows = await db.customSelect(
    'SELECT $bucketSql AS bucket, e.type AS type, '
    '${column(AggregateBy.category, 'e.category_id')} AS category_id, '
    '${column(AggregateBy.project, 'e.project_id')} AS project_id, '
    '${column(AggregateBy.event, 'e.event_id')} AS event_id, '
    '${column(AggregateBy.tag, 'et.tag_id')} AS tag_id, '
    'SUM(e.amount) AS total, COUNT(*) AS cnt '
    'FROM expenses e${byTag ? ' JOIN expense_tags et ON et.expense_id = e.id' : ''} '
    'WHERE ${where.join(' AND ')} '
    'GROUP BY ${['bucket', 'e.type', ...dimensions].join(', ')}',
    variables: variables,
  ).get();

  return [
    for (final row in rows)
      AmountGroup(
        bucket: row.read<int>('bucket'),
        type: row.read<String>('type'),
        total: row.read<int>('total'),
        count: row.read<int>('cnt'),
        categoryId: row.readNullable<String>('category_id'),
        projectId: row.readNullable<String>('project_id'),
        eventId: row.readNullable<String>('event_id'),
        tagId: row.readNullable<String>('tag_id'),
      ),
  ];
}

/// Start of every day of [month] (local time), for per-day [aggregateExpenses]
/// buckets: bucket `i` is day `i + 1`.
List<DateTime> daysOf(DateTime month) {
  final lastDay = DateTime(month.year, month.month + 1, 0).day;
  return [for (var d = 1; d <= lastDay; d++) DateTime(month.year, month.month, d)];
}

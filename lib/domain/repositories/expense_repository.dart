import 'dart:math';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';

const _uuid = Uuid();

class ExpenseFilters {
  const ExpenseFilters({
    this.types = const {},
    this.categoryIds = const {},
    this.tagIds = const {},
    this.paymentMethodIds = const {},
    this.eventIds = const {},
    this.projectIds = const {},
    this.amountMin,
    this.amountMax,
    this.dateFrom,
    this.dateTo,
  });

  /// Each set is a multi-select: a transaction matches when it has *any* of
  /// the selected values (OR within a dimension, AND across dimensions). An
  /// empty set doesn't filter that dimension.
  final Set<String> types;

  /// Picking a parent category matches its whole subtree.
  final Set<String> categoryIds;

  /// Matches transactions carrying at least one of these tags.
  final Set<String> tagIds;
  final Set<String> paymentMethodIds;
  final Set<String> eventIds;
  final Set<String> projectIds;

  /// Inclusive bounds on the (always positive) amount, in cents.
  final int? amountMin;
  final int? amountMax;

  /// Inclusive day bounds: only the calendar day counts, the time of day is
  /// ignored. A transaction at 18:00 on [dateTo]'s day is included.
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// Whether both date bounds are set and [dateFrom]'s day is after [dateTo]'s.
  bool get hasInvertedDates {
    if (dateFrom == null || dateTo == null) return false;
    return DateTime(dateFrom!.year, dateFrom!.month, dateFrom!.day)
        .isAfter(DateTime(dateTo!.year, dateTo!.month, dateTo!.day));
  }

  /// Whether both amount bounds are set and [amountMin] exceeds [amountMax].
  bool get hasInvertedAmounts => amountMin != null && amountMax != null && amountMin! > amountMax!;

  ExpenseFilters copyWith({
    Set<String>? types,
    Set<String>? categoryIds,
    Set<String>? tagIds,
    Set<String>? paymentMethodIds,
    Set<String>? eventIds,
    Set<String>? projectIds,
    int? Function()? amountMin,
    int? Function()? amountMax,
    DateTime? Function()? dateFrom,
    DateTime? Function()? dateTo,
  }) =>
      ExpenseFilters(
        types: types ?? this.types,
        categoryIds: categoryIds ?? this.categoryIds,
        tagIds: tagIds ?? this.tagIds,
        paymentMethodIds: paymentMethodIds ?? this.paymentMethodIds,
        eventIds: eventIds ?? this.eventIds,
        projectIds: projectIds ?? this.projectIds,
        amountMin: amountMin != null ? amountMin() : this.amountMin,
        amountMax: amountMax != null ? amountMax() : this.amountMax,
        dateFrom: dateFrom != null ? dateFrom() : this.dateFrom,
        dateTo: dateTo != null ? dateTo() : this.dateTo,
      );

  /// A copy with [dateFrom] and [dateTo] exchanged.
  ExpenseFilters withSwappedDates() => copyWith(dateFrom: () => dateTo, dateTo: () => dateFrom);

  /// A copy with [amountMin] and [amountMax] exchanged.
  ExpenseFilters withSwappedAmounts() => copyWith(amountMin: () => amountMax, amountMax: () => amountMin);
}

class ExpenseRepository {
  ExpenseRepository(this._db);

  final AppDatabase _db;

  static const pageSize = 100;

  /// Most-recent-first with a total order: many rows share a `date` (edited
  /// ones at 00:00, recurring ones), and LIMIT/OFFSET over ties in undefined
  /// order can repeat or skip rows across pages. createdAt then id break ties.
  List<OrderingTerm> get _newestFirst => [
        OrderingTerm.desc(_db.expenses.date),
        OrderingTerm.desc(_db.expenses.createdAt),
        OrderingTerm.desc(_db.expenses.id),
      ];

  JoinedSelectStatement<HasResultSet, dynamic> _filteredQuery(ExpenseFilters filters) {
    final e = _db.expenses;
    final query = _db.select(e).join([]);

    final conditions = <Expression<bool>>[];
    if (filters.types.isNotEmpty) conditions.add(e.type.isIn(filters.types));
    if (filters.categoryIds.isNotEmpty) {
      conditions.add(_inCategorySubtrees(filters.categoryIds));
    }
    if (filters.tagIds.isNotEmpty) {
      // A subquery rather than a join: a row with several matching tags must
      // still be listed once.
      final t = _db.expenseTags;
      conditions.add(e.id.isInQuery(
        _db.selectOnly(t)
          ..addColumns([t.expenseId])
          ..where(t.tagId.isIn(filters.tagIds)),
      ));
    }
    if (filters.paymentMethodIds.isNotEmpty) {
      conditions.add(e.paymentMethodId.isIn(filters.paymentMethodIds));
    }
    if (filters.eventIds.isNotEmpty) conditions.add(e.eventId.isIn(filters.eventIds));
    if (filters.projectIds.isNotEmpty) conditions.add(e.projectId.isIn(filters.projectIds));
    if (filters.amountMin != null) conditions.add(e.amount.isBiggerOrEqualValue(filters.amountMin!));
    if (filters.amountMax != null) conditions.add(e.amount.isSmallerOrEqualValue(filters.amountMax!));
    if (filters.dateFrom != null) {
      final from = filters.dateFrom!;
      conditions.add(e.date.isBiggerOrEqualValue(DateTime(from.year, from.month, from.day)));
    }
    if (filters.dateTo != null) {
      // Pickers return the day at 00:00, but transactions carry a time: compare
      // against the start of the next day so the whole last day is included.
      final to = filters.dateTo!;
      conditions.add(e.date.isSmallerThanValue(DateTime(to.year, to.month, to.day + 1)));
    }
    for (final c in conditions) {
      query.where(c);
    }
    return query;
  }

  /// `category_id IN {each of categoryIds + all their descendants}`. Only
  /// leaves are assigned to transactions, so filtering by a parent must match
  /// its whole subtree. Resolved in SQL (recursive CTE) to keep the query
  /// synchronous and fully DB-side; the ids are inlined as escaped string
  /// literals because [CustomExpression] has no bind variables.
  Expression<bool> _inCategorySubtrees(Set<String> categoryIds) {
    final seeds = categoryIds.map((id) => "('${id.replaceAll("'", "''")}')").join(', ');
    return CustomExpression<bool>(
      'expenses.category_id IN ('
      'WITH RECURSIVE subtree(id) AS ('
      'VALUES $seeds '
      'UNION SELECT c.id FROM categories c JOIN subtree s ON c.parent_id = s.id'
      ') SELECT id FROM subtree)',
      watchedTables: [_db.categories],
    );
  }

  /// Paginated, most-recent-first, filtered entirely in SQL (no client-side
  /// partial filtering / "filtro parcial" warning like the web app has).
  ///
  /// Keyset pagination (BL-065): pass the last row of the previous page as
  /// [after] to get the next one. Unlike LIMIT/OFFSET, page N doesn't scan and
  /// discard N×[pageSize] rows, and the `idx_expenses_order` index serves the
  /// ORDER BY directly. The cursor follows the same total order as
  /// [_newestFirst] (date, createdAt, id), so ties never repeat or skip rows.
  Future<List<Expense>> list({ExpenseFilters filters = const ExpenseFilters(), Expense? after}) {
    final query = _filteredQuery(filters)
      ..orderBy(_newestFirst)
      ..limit(pageSize);
    if (after != null) {
      final e = _db.expenses;
      // `date <= cursor` up front lets SQLite seek the index instead of
      // filtering from the newest row.
      query.where(e.date.isSmallerOrEqualValue(after.date) &
          (e.date.isSmallerThanValue(after.date) |
              (e.date.equals(after.date) &
                  (e.createdAt.isSmallerThanValue(after.createdAt) |
                      (e.createdAt.equals(after.createdAt) & e.id.isSmallerThanValue(after.id))))));
    }

    return query.map((row) => row.readTable(_db.expenses)).get();
  }

  /// Unpaginated — used by the Dashboard/Analytics month views, which need the
  /// full month's data (never more than a few hundred rows) rather than a
  /// fixed-size page.
  Future<List<Expense>> listAll({ExpenseFilters filters = const ExpenseFilters()}) {
    final query = _filteredQuery(filters)..orderBy(_newestFirst);
    return query.map((row) => row.readTable(_db.expenses)).get();
  }

  /// Live variant of [listAll] — emits again on any write to `expenses` (or
  /// `expenseTags` when [ExpenseFilters.tagIds] is set), so callers never need
  /// to manually cache/invalidate (e.g. after confirming a recurring
  /// occurrence, which inserts directly into `expenses`).
  Stream<List<Expense>> watchAll({ExpenseFilters filters = const ExpenseFilters()}) {
    final query = _filteredQuery(filters)..orderBy(_newestFirst);
    return query.map((row) => row.readTable(_db.expenses)).watch();
  }

  Future<Expense?> byId(String id) {
    return (_db.select(_db.expenses)..where((e) => e.id.equals(id))).getSingleOrNull();
  }

  Future<List<String>> tagIdsOf(String expenseId) async {
    final rows = await (_db.select(_db.expenseTags)
          ..where((t) => t.expenseId.equals(expenseId)))
        .get();
    return rows.map((r) => r.tagId).toList();
  }

  /// Tag ids of many expenses at once: expense id → its tag ids (expenses
  /// without tags are absent). One query per [_inChunk] ids instead of one per
  /// expense (BL-018); chunked to stay under SQLite's bound-variable limit.
  Future<Map<String, List<String>>> tagIdsByExpense(Iterable<String> expenseIds) async {
    final ids = expenseIds.toList();
    final result = <String, List<String>>{};
    for (var i = 0; i < ids.length; i += _inChunk) {
      final chunk = ids.sublist(i, min(i + _inChunk, ids.length));
      final rows = await (_db.select(_db.expenseTags)..where((t) => t.expenseId.isIn(chunk))).get();
      for (final r in rows) {
        (result[r.expenseId] ??= []).add(r.tagId);
      }
    }
    return result;
  }

  static const _inChunk = 900;

  /// [amountCents] is always stored positive; the sign is derived from [type]
  /// at display/aggregation time, never in storage.
  Future<String> create({
    required int amountCents,
    required String currency,
    required String type,
    required DateTime date,
    String? description,
    String? notes,
    String? categoryId,
    String? paymentMethodId,
    String? eventId,
    String? projectId,
    List<String> tagIds = const [],
  }) async {
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db.into(_db.expenses).insert(
            ExpensesCompanion.insert(
              id: id,
              amount: amountCents,
              currency: currency,
              type: type,
              date: date,
              description: Value(description),
              notes: Value(notes),
              categoryId: Value(categoryId),
              paymentMethodId: Value(paymentMethodId),
              eventId: Value(eventId),
              projectId: Value(projectId),
            ),
          );
      // Dedup: `expense_tags` PK is {expenseId, tagId}, so a repeated tagId
      // would raise a UNIQUE violation and roll back the whole insert.
      for (final tagId in tagIds.toSet()) {
        await _db.into(_db.expenseTags).insert(
              ExpenseTagsCompanion.insert(expenseId: id, tagId: tagId),
            );
      }
    });
    return id;
  }

  /// Currency is intentionally never part of the update payload — it is frozen
  /// at creation (see plan §2, "moneda inmutable").
  Future<void> update(
    String id, {
    int? amountCents,
    String? type,
    DateTime? date,
    String? description,
    String? notes,
    String? categoryId,
    String? paymentMethodId,
    String? eventId,
    String? projectId,
    List<String>? tagIds,
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.expenses)..where((e) => e.id.equals(id))).write(
        ExpensesCompanion(
          amount: amountCents == null ? const Value.absent() : Value(amountCents),
          type: type == null ? const Value.absent() : Value(type),
          date: date == null ? const Value.absent() : Value(date),
          description: Value(description),
          notes: Value(notes),
          categoryId: Value(categoryId),
          paymentMethodId: Value(paymentMethodId),
          eventId: Value(eventId),
          projectId: Value(projectId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (tagIds != null) {
        await (_db.delete(_db.expenseTags)..where((t) => t.expenseId.equals(id))).go();
        // Dedup: see `create` — repeated tagIds violate the {expenseId, tagId} PK.
        for (final tagId in tagIds.toSet()) {
          await _db.into(_db.expenseTags).insert(
                ExpenseTagsCompanion.insert(expenseId: id, tagId: tagId),
              );
        }
      }
    });
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.expenses)..where((e) => e.id.equals(id))).go();
  }
}

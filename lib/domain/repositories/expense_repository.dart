import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';

const _uuid = Uuid();

class ExpenseFilters {
  const ExpenseFilters({
    this.type,
    this.categoryId,
    this.tagId,
    this.paymentMethodId,
    this.eventId,
    this.projectId,
    this.dateFrom,
    this.dateTo,
  });

  final String? type;
  final String? categoryId;
  final String? tagId;
  final String? paymentMethodId;
  final String? eventId;
  final String? projectId;

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

  /// A copy with [dateFrom] and [dateTo] exchanged.
  ExpenseFilters withSwappedDates() => ExpenseFilters(
        type: type,
        categoryId: categoryId,
        tagId: tagId,
        paymentMethodId: paymentMethodId,
        eventId: eventId,
        projectId: projectId,
        dateFrom: dateTo,
        dateTo: dateFrom,
      );
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
    final query = _db.select(_db.expenses).join([
      if (filters.tagId != null)
        innerJoin(
          _db.expenseTags,
          _db.expenseTags.expenseId.equalsExp(_db.expenses.id) &
              _db.expenseTags.tagId.equals(filters.tagId!),
        ),
    ]);

    final conditions = <Expression<bool>>[];
    if (filters.type != null) conditions.add(_db.expenses.type.equals(filters.type!));
    if (filters.categoryId != null) {
      conditions.add(_inCategorySubtree(filters.categoryId!));
    }
    if (filters.paymentMethodId != null) {
      conditions.add(_db.expenses.paymentMethodId.equals(filters.paymentMethodId!));
    }
    if (filters.eventId != null) conditions.add(_db.expenses.eventId.equals(filters.eventId!));
    if (filters.projectId != null) {
      conditions.add(_db.expenses.projectId.equals(filters.projectId!));
    }
    if (filters.dateFrom != null) {
      final from = filters.dateFrom!;
      conditions.add(_db.expenses.date.isBiggerOrEqualValue(DateTime(from.year, from.month, from.day)));
    }
    if (filters.dateTo != null) {
      // Pickers return the day at 00:00, but transactions carry a time: compare
      // against the start of the next day so the whole last day is included.
      final to = filters.dateTo!;
      conditions.add(_db.expenses.date.isSmallerThanValue(DateTime(to.year, to.month, to.day + 1)));
    }
    for (final c in conditions) {
      query.where(c);
    }
    return query;
  }

  /// `category_id IN {categoryId + all its descendants}`. Only leaves are
  /// assigned to transactions, so filtering by a parent must match its whole
  /// subtree. Resolved in SQL (recursive CTE) to keep the query synchronous and
  /// fully DB-side; the id is inlined as an escaped string literal because
  /// [CustomExpression] has no bind variables.
  Expression<bool> _inCategorySubtree(String categoryId) {
    final literal = "'${categoryId.replaceAll("'", "''")}'";
    return CustomExpression<bool>(
      'expenses.category_id IN ('
      'WITH RECURSIVE subtree(id) AS ('
      'SELECT $literal '
      'UNION ALL SELECT c.id FROM categories c JOIN subtree s ON c.parent_id = s.id'
      ') SELECT id FROM subtree)',
      watchedTables: [_db.categories],
    );
  }

  /// Paginated, most-recent-first, filtered entirely in SQL (no client-side
  /// partial filtering / "filtro parcial" warning like the web app has).
  Future<List<Expense>> list({ExpenseFilters filters = const ExpenseFilters(), int page = 0}) {
    final query = _filteredQuery(filters)
      ..orderBy(_newestFirst)
      ..limit(pageSize, offset: page * pageSize);

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
  /// `expenseTags` when [ExpenseFilters.tagId] is set), so callers never need
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

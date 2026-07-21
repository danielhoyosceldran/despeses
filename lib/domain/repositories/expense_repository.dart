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
  final DateTime? dateFrom;
  final DateTime? dateTo;
}

class ExpenseRepository {
  ExpenseRepository(this._db);

  final AppDatabase _db;

  static const pageSize = 100;

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
      conditions.add(_db.expenses.categoryId.equals(filters.categoryId!));
    }
    if (filters.paymentMethodId != null) {
      conditions.add(_db.expenses.paymentMethodId.equals(filters.paymentMethodId!));
    }
    if (filters.eventId != null) conditions.add(_db.expenses.eventId.equals(filters.eventId!));
    if (filters.projectId != null) {
      conditions.add(_db.expenses.projectId.equals(filters.projectId!));
    }
    if (filters.dateFrom != null) {
      conditions.add(_db.expenses.date.isBiggerOrEqualValue(filters.dateFrom!));
    }
    if (filters.dateTo != null) {
      conditions.add(_db.expenses.date.isSmallerOrEqualValue(filters.dateTo!));
    }
    for (final c in conditions) {
      query.where(c);
    }
    return query;
  }

  /// Paginated, most-recent-first, filtered entirely in SQL (no client-side
  /// partial filtering / "filtro parcial" warning like the web app has).
  Future<List<Expense>> list({ExpenseFilters filters = const ExpenseFilters(), int page = 0}) {
    final query = _filteredQuery(filters)
      ..orderBy([OrderingTerm.desc(_db.expenses.date)])
      ..limit(pageSize, offset: page * pageSize);

    return query.map((row) => row.readTable(_db.expenses)).get();
  }

  /// Unpaginated — used by the Dashboard/Analytics month views, which need the
  /// full month's data (never more than a few hundred rows) rather than a
  /// fixed-size page.
  Future<List<Expense>> listAll({ExpenseFilters filters = const ExpenseFilters()}) {
    final query = _filteredQuery(filters)..orderBy([OrderingTerm.desc(_db.expenses.date)]);
    return query.map((row) => row.readTable(_db.expenses)).get();
  }

  /// Live variant of [listAll] — emits again on any write to `expenses` (or
  /// `expenseTags` when [ExpenseFilters.tagId] is set), so callers never need
  /// to manually cache/invalidate (e.g. after confirming a recurring
  /// occurrence, which inserts directly into `expenses`).
  Stream<List<Expense>> watchAll({ExpenseFilters filters = const ExpenseFilters()}) {
    final query = _filteredQuery(filters)..orderBy([OrderingTerm.desc(_db.expenses.date)]);
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
      for (final tagId in tagIds) {
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
        for (final tagId in tagIds) {
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

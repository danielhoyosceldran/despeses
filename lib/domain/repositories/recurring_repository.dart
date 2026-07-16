import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';

const _uuid = Uuid();

/// Recurring transactions (feature 3.13).
///
/// A [Recurring] is a template + schedule. It never shows up in listings or
/// analytics. Instead [materializeDue] walks each active template's due dates
/// and drops a [RecurringOccurrence] into the pending inbox for every date that
/// has arrived (catching up if the app wasn't opened for a while). The user
/// then [confirm]s an occurrence — which creates a real [Expense] — or [skip]s
/// it. Materialization is idempotent thanks to the `{recurringId, dueDate}`
/// unique key, so running it twice never double-posts.
class RecurringRepository {
  RecurringRepository(this._db);

  final AppDatabase _db;

  /// Safety cap on how many occurrences a single template can catch up in one
  /// pass, so a weekly template left dormant for years can't spawn thousands of
  /// rows at once.
  static const _maxCatchUp = 200;

  // --- Templates -----------------------------------------------------------

  Future<List<Recurring>> listTemplates() {
    return (_db.select(_db.recurrings)
          ..orderBy([(r) => OrderingTerm.desc(r.active), (r) => OrderingTerm.asc(r.nextDate)]))
        .get();
  }

  Future<Recurring?> templateById(String id) {
    return (_db.select(_db.recurrings)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  Future<List<String>> tagIdsOf(String recurringId) async {
    final rows = await (_db.select(_db.recurringTags)
          ..where((t) => t.recurringId.equals(recurringId)))
        .get();
    return rows.map((r) => r.tagId).toList();
  }

  /// [amountCents] is stored positive; the sign is derived from [type] at
  /// display/aggregation time, exactly like [Expense].
  Future<String> create({
    required int amountCents,
    required String currency,
    required String type,
    required String frequency,
    required DateTime startDate,
    DateTime? endDate,
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
      await _db.into(_db.recurrings).insert(
            RecurringsCompanion.insert(
              id: id,
              amount: amountCents,
              currency: currency,
              type: type,
              frequency: frequency,
              startDate: startDate,
              // First fire is the start date itself.
              nextDate: startDate,
              endDate: Value(endDate),
              description: Value(description),
              notes: Value(notes),
              categoryId: Value(categoryId),
              paymentMethodId: Value(paymentMethodId),
              eventId: Value(eventId),
              projectId: Value(projectId),
            ),
          );
      for (final tagId in tagIds) {
        await _db.into(_db.recurringTags).insert(
              RecurringTagsCompanion.insert(recurringId: id, tagId: tagId),
            );
      }
    });
    return id;
  }

  /// Edits a template. Schedule (frequency/startDate) is editable here; changing
  /// [startDate] also resets [nextDate] so the new anchor takes effect from the
  /// next materialization. Already-materialized occurrences keep their snapshot.
  Future<void> update(
    String id, {
    int? amountCents,
    String? type,
    String? frequency,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    String? description,
    String? notes,
    String? categoryId,
    String? paymentMethodId,
    String? eventId,
    String? projectId,
    List<String>? tagIds,
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.recurrings)..where((r) => r.id.equals(id))).write(
        RecurringsCompanion(
          amount: amountCents == null ? const Value.absent() : Value(amountCents),
          type: type == null ? const Value.absent() : Value(type),
          frequency: frequency == null ? const Value.absent() : Value(frequency),
          startDate: startDate == null ? const Value.absent() : Value(startDate),
          // Re-anchor the schedule when startDate moves.
          nextDate: startDate == null ? const Value.absent() : Value(startDate),
          endDate: clearEndDate ? const Value(null) : (endDate == null ? const Value.absent() : Value(endDate)),
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
        await (_db.delete(_db.recurringTags)..where((t) => t.recurringId.equals(id))).go();
        for (final tagId in tagIds) {
          await _db.into(_db.recurringTags).insert(
                RecurringTagsCompanion.insert(recurringId: id, tagId: tagId),
              );
        }
      }
    });
  }

  Future<void> setActive(String id, bool active) async {
    await (_db.update(_db.recurrings)..where((r) => r.id.equals(id))).write(
      RecurringsCompanion(active: Value(active), updatedAt: Value(DateTime.now())),
    );
  }

  /// Deleting a template cascades to its tags and any pending occurrences.
  Future<void> delete(String id) async {
    await (_db.delete(_db.recurrings)..where((r) => r.id.equals(id))).go();
  }

  // --- Pending inbox -------------------------------------------------------

  Future<List<RecurringOccurrence>> listPending() {
    return (_db.select(_db.recurringOccurrences)
          ..orderBy([(o) => OrderingTerm.asc(o.dueDate)]))
        .get();
  }

  Stream<List<RecurringOccurrence>> watchPending() {
    return (_db.select(_db.recurringOccurrences)
          ..orderBy([(o) => OrderingTerm.asc(o.dueDate)]))
        .watch();
  }

  Stream<int> watchPendingCount() {
    final count = _db.recurringOccurrences.id.count();
    final query = _db.selectOnly(_db.recurringOccurrences)..addColumns([count]);
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// Confirms a pending occurrence into a real [Expense] (copying the template's
  /// current tags) and removes it from the inbox — all in one transaction.
  /// Returns the new expense id.
  Future<String> confirm(RecurringOccurrence occ) async {
    final expenseId = _uuid.v4();
    await _db.transaction(() async {
      final tagIds = await tagIdsOf(occ.recurringId);
      await _db.into(_db.expenses).insert(
            ExpensesCompanion.insert(
              id: expenseId,
              amount: occ.amount,
              currency: occ.currency,
              type: occ.type,
              date: occ.dueDate,
              description: Value(occ.description),
              notes: Value(occ.notes),
              categoryId: Value(occ.categoryId),
              paymentMethodId: Value(occ.paymentMethodId),
              eventId: Value(occ.eventId),
              projectId: Value(occ.projectId),
            ),
          );
      for (final tagId in tagIds) {
        await _db.into(_db.expenseTags).insert(
              ExpenseTagsCompanion.insert(expenseId: expenseId, tagId: tagId),
            );
      }
      await (_db.delete(_db.recurringOccurrences)..where((o) => o.id.equals(occ.id))).go();
    });
    return expenseId;
  }

  /// Discards a pending occurrence without creating an expense.
  Future<void> skip(String occurrenceId) async {
    await (_db.delete(_db.recurringOccurrences)..where((o) => o.id.equals(occurrenceId))).go();
  }

  // --- Materialization engine ---------------------------------------------

  /// Walks every active template and drops a pending occurrence for each due
  /// date at or before today, advancing the template's [Recurring.nextDate]
  /// past today and deactivating it once its [Recurring.endDate] passes.
  ///
  /// Idempotent: safe to call on every app launch. [now] is injectable for
  /// tests. Returns the number of occurrences created.
  Future<int> materializeDue({DateTime? now}) async {
    final today = _dateOnly(now ?? DateTime.now());
    final due = await (_db.select(_db.recurrings)
          ..where((r) => r.active.equals(true))
          ..where((r) => r.nextDate.isSmallerOrEqualValue(_endOfDay(today))))
        .get();

    var created = 0;
    for (final t in due) {
      created += await _materializeTemplate(t, today);
    }
    return created;
  }

  Future<int> _materializeTemplate(Recurring t, DateTime today) async {
    final end = t.endDate == null ? null : _dateOnly(t.endDate!);
    var cursor = _dateOnly(t.nextDate);
    final dueDates = <DateTime>[];
    while (dueDates.length < _maxCatchUp &&
        !cursor.isAfter(today) &&
        (end == null || !cursor.isAfter(end))) {
      dueDates.add(cursor);
      cursor = _advance(cursor, t.frequency, t.startDate);
    }
    if (dueDates.isEmpty) return 0;

    final stillActive = end == null || !cursor.isAfter(end);
    await _db.transaction(() async {
      for (final d in dueDates) {
        await _db.into(_db.recurringOccurrences).insert(
              RecurringOccurrencesCompanion.insert(
                id: _uuid.v4(),
                recurringId: t.id,
                dueDate: d,
                amount: t.amount,
                currency: t.currency,
                type: t.type,
                description: Value(t.description),
                notes: Value(t.notes),
                categoryId: Value(t.categoryId),
                paymentMethodId: Value(t.paymentMethodId),
                eventId: Value(t.eventId),
                projectId: Value(t.projectId),
              ),
              // Idempotency: a prior half-completed pass may already hold some of
              // these (recurringId, dueDate) pairs.
              mode: InsertMode.insertOrIgnore,
            );
      }
      await (_db.update(_db.recurrings)..where((r) => r.id.equals(t.id))).write(
        RecurringsCompanion(
          nextDate: Value(cursor),
          active: Value(stillActive),
          lastPostedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
    return dueDates.length;
  }

  /// Advances [from] by one period. Monthly and yearly re-anchor on [anchor]'s
  /// day-of-month (and month, for yearly), clamping to the target month's
  /// length — so a Jan-31 monthly template fires on Feb-28 then Mar-31 again,
  /// and a Feb-29 yearly template falls back to Feb-28 in common years.
  static DateTime _advance(DateTime from, String frequency, DateTime anchor) {
    switch (frequency) {
      case 'weekly':
        return from.add(const Duration(days: 7));
      case 'yearly':
        final year = from.year + 1;
        return DateTime(year, anchor.month, _clampDay(year, anchor.month, anchor.day));
      case 'monthly':
      default:
        final nextMonthFirst = DateTime(from.year, from.month + 1);
        return DateTime(
          nextMonthFirst.year,
          nextMonthFirst.month,
          _clampDay(nextMonthFirst.year, nextMonthFirst.month, anchor.day),
        );
    }
  }

  static int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  static int _clampDay(int year, int month, int day) {
    final max = _daysInMonth(year, month);
    return day < max ? day : max;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}

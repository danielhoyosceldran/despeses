import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/recurring_repository.dart';

void main() {
  late AppDatabase db;
  late RecurringRepository recurring;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    recurring = RecurringRepository(db);
  });

  tearDown(() async => db.close());

  Future<String> addMonthly({
    required DateTime start,
    DateTime? end,
    int amount = 1000,
    String type = 'expense',
    String frequency = 'monthly',
  }) {
    return recurring.create(
      amountCents: amount,
      currency: 'EUR',
      type: type,
      frequency: frequency,
      startDate: start,
      endDate: end,
      description: 'Rent',
    );
  }

  test('materialize creates one occurrence per elapsed period and advances nextDate past today', () async {
    // Monthly template starting 3 months before "today".
    await addMonthly(start: DateTime(2026, 1, 1));

    final created = await recurring.materializeDue(now: DateTime(2026, 3, 15));

    expect(created, 3); // Jan 1, Feb 1, Mar 1
    final pending = await recurring.listPending();
    expect(pending.map((o) => o.dueDate).toList(),
        [DateTime(2026, 1, 1), DateTime(2026, 2, 1), DateTime(2026, 3, 1)]);

    final template = (await recurring.listTemplates()).single;
    expect(template.nextDate, DateTime(2026, 4, 1)); // next future date
    expect(template.active, isTrue);
  });

  test('materialize is idempotent — running twice does not double-post', () async {
    await addMonthly(start: DateTime(2026, 1, 1));

    await recurring.materializeDue(now: DateTime(2026, 3, 15));
    final again = await recurring.materializeDue(now: DateTime(2026, 3, 15));

    expect(again, 0);
    expect((await recurring.listPending()).length, 3);
  });

  test('monthly day-of-month anchor clamps in short months then restores', () async {
    // Anchored on the 31st: Feb has no 31st → clamps to 28, but March restores 31.
    await addMonthly(start: DateTime(2026, 1, 31));

    await recurring.materializeDue(now: DateTime(2026, 3, 31));

    final due = (await recurring.listPending()).map((o) => o.dueDate).toList();
    expect(due, [DateTime(2026, 1, 31), DateTime(2026, 2, 28), DateTime(2026, 3, 31)]);
  });

  test('weekly advances by 7 days', () async {
    await addMonthly(start: DateTime(2026, 1, 1), frequency: 'weekly');

    await recurring.materializeDue(now: DateTime(2026, 1, 20));

    final due = (await recurring.listPending()).map((o) => o.dueDate).toList();
    expect(due, [DateTime(2026, 1, 1), DateTime(2026, 1, 8), DateTime(2026, 1, 15)]);
  });

  test('yearly advances by a year and clamps Feb-29 anchor in common years', () async {
    await addMonthly(start: DateTime(2024, 2, 29), frequency: 'yearly');

    await recurring.materializeDue(now: DateTime(2026, 6, 1));

    final due = (await recurring.listPending()).map((o) => o.dueDate).toList();
    // 2024 leap, 2025 clamps to Feb 28, 2026 clamps to Feb 28.
    expect(due, [DateTime(2024, 2, 29), DateTime(2025, 2, 28), DateTime(2026, 2, 28)]);
  });

  test('endDate stops materialization and deactivates the template', () async {
    await addMonthly(start: DateTime(2026, 1, 1), end: DateTime(2026, 2, 28));

    final created = await recurring.materializeDue(now: DateTime(2026, 6, 1));

    expect(created, 2); // Jan and Feb only
    final template = (await recurring.listTemplates()).single;
    expect(template.active, isFalse);
  });

  test('templates not yet due produce nothing', () async {
    await addMonthly(start: DateTime(2026, 12, 1));

    final created = await recurring.materializeDue(now: DateTime(2026, 3, 15));

    expect(created, 0);
    expect(await recurring.listPending(), isEmpty);
  });

  test('confirm creates a real expense from the snapshot and clears the occurrence', () async {
    await addMonthly(start: DateTime(2026, 1, 1), amount: 80000);
    await recurring.materializeDue(now: DateTime(2026, 1, 15));
    final occ = (await recurring.listPending()).single;

    final expenseId = await recurring.confirm(occ);

    final expense = await (db.select(db.expenses)..where((e) => e.id.equals(expenseId))).getSingle();
    expect(expense.amount, 80000);
    expect(expense.type, 'expense');
    expect(expense.date, DateTime(2026, 1, 1));
    expect(await recurring.listPending(), isEmpty);
  });

  test('confirm copies the template\'s current tags onto the expense', () async {
    // Seed a tag group + tag to satisfy FK constraints.
    await db.into(db.tagGroups).insert(
        TagGroupsCompanion.insert(id: 'g1', name: 'grp'));
    await db.into(db.tags).insert(
        TagsCompanion.insert(id: 't1', tagGroupId: 'g1', name: 'tag'));
    final id = await recurring.create(
      amountCents: 1000,
      currency: 'EUR',
      type: 'expense',
      frequency: 'monthly',
      startDate: DateTime(2026, 1, 1),
      tagIds: const ['t1'],
    );
    await recurring.materializeDue(now: DateTime(2026, 1, 15));
    final occ = (await recurring.listPending()).single;
    expect(occ.recurringId, id);

    final expenseId = await recurring.confirm(occ);

    final tagRows = await (db.select(db.expenseTags)
          ..where((t) => t.expenseId.equals(expenseId)))
        .get();
    expect(tagRows.map((r) => r.tagId).toList(), ['t1']);
  });

  test('skip discards an occurrence without creating an expense', () async {
    await addMonthly(start: DateTime(2026, 1, 1));
    await recurring.materializeDue(now: DateTime(2026, 1, 15));
    final occ = (await recurring.listPending()).single;

    await recurring.skip(occ.id);

    expect(await recurring.listPending(), isEmpty);
    expect(await db.select(db.expenses).get(), isEmpty);
  });

  test('inactive templates are skipped by the materializer', () async {
    final id = await addMonthly(start: DateTime(2026, 1, 1));
    await recurring.setActive(id, false);

    final created = await recurring.materializeDue(now: DateTime(2026, 3, 15));

    expect(created, 0);
  });

  test('deleting a template cascades to its pending occurrences', () async {
    final id = await addMonthly(start: DateTime(2026, 1, 1));
    await recurring.materializeDue(now: DateTime(2026, 3, 15));
    expect((await recurring.listPending()).length, 3);

    await recurring.delete(id);

    expect(await recurring.listPending(), isEmpty);
  });
}

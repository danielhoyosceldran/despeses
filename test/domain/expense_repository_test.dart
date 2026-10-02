import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/expense_repository.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExpenseRepository(db);
  });

  tearDown(() async => db.close());

  test('create/update roundtrip never changes currency, and updates tags', () async {
    final tag = (await db.select(db.tags).get()).first;
    final otherTag = (await db.select(db.tags).get())[1];

    final id = await repo.create(
      amountCents: 1250,
      currency: 'EUR',
      type: 'expense',
      date: DateTime(2026, 1, 10),
      description: 'Groceries',
      tagIds: [tag.id],
    );

    var stored = await repo.byId(id);
    expect(stored!.currency, 'EUR');
    expect(stored.amount, 1250);
    expect(await repo.tagIdsOf(id), [tag.id]);

    await repo.update(id, amountCents: 1500, description: 'Groceries v2', tagIds: [otherTag.id]);

    stored = await repo.byId(id);
    expect(stored!.currency, 'EUR');
    expect(stored.amount, 1500);
    expect(stored.description, 'Groceries v2');
    expect(await repo.tagIdsOf(id), [otherTag.id]);
  });

  test('list filters by type entirely in SQL and orders most-recent-first', () async {
    await repo.create(amountCents: 100, currency: 'EUR', type: 'expense', date: DateTime(2026, 1, 1));
    await repo.create(amountCents: 200, currency: 'EUR', type: 'income', date: DateTime(2026, 1, 2));
    await repo.create(amountCents: 300, currency: 'EUR', type: 'expense', date: DateTime(2026, 1, 3));

    final expenses = await repo.list(filters: const ExpenseFilters(type: 'expense'));
    expect(expenses.length, 2);
    expect(expenses.first.amount, 300); // most recent first
  });

  test('listAll returns every matching row unpaginated, for month/dashboard views', () async {
    for (var i = 0; i < 150; i++) {
      await repo.create(amountCents: 100, currency: 'EUR', type: 'expense', date: DateTime(2026, 1, 1));
    }
    final paginated = await repo.list();
    final all = await repo.listAll();
    expect(paginated.length, ExpenseRepository.pageSize);
    expect(all.length, 150);
  });

  test('delete removes the expense', () async {
    final id = await repo.create(amountCents: 100, currency: 'EUR', type: 'expense', date: DateTime(2026, 1, 1));
    await repo.delete(id);
    expect(await repo.byId(id), isNull);
  });

  test('dateTo includes the whole last day regardless of time', () async {
    Future<void> add(DateTime date) => repo.create(
          amountCents: 100,
          currency: 'EUR',
          type: 'expense',
          date: date,
        );
    await add(DateTime(2026, 3, 1, 9)); // first day, morning
    await add(DateTime(2026, 3, 31, 18)); // last day, 18:00
    await add(DateTime(2026, 4, 1, 0, 0, 1)); // just past the range
    await add(DateTime(2026, 2, 28, 23, 59)); // just before the range

    final rows = await repo.listAll(
      filters: ExpenseFilters(dateFrom: DateTime(2026, 3, 1), dateTo: DateTime(2026, 3, 31)),
    );

    expect(rows.map((e) => e.date).toSet(), {DateTime(2026, 3, 1, 9), DateTime(2026, 3, 31, 18)});
  });

  test('hasInvertedDates compares days and withSwappedDates exchanges them', () {
    final inverted = ExpenseFilters(type: 'expense', dateFrom: DateTime(2026, 3, 10), dateTo: DateTime(2026, 3, 5));
    final sameDay = ExpenseFilters(dateFrom: DateTime(2026, 3, 5, 18), dateTo: DateTime(2026, 3, 5));

    expect(inverted.hasInvertedDates, isTrue);
    expect(sameDay.hasInvertedDates, isFalse);
    expect(const ExpenseFilters().hasInvertedDates, isFalse);
    final swapped = inverted.withSwappedDates();
    expect(swapped.dateFrom, DateTime(2026, 3, 5));
    expect(swapped.dateTo, DateTime(2026, 3, 10));
    expect(swapped.type, 'expense');
  });

  test('pagination over many same-date rows neither repeats nor skips', () async {
    final total = ExpenseRepository.pageSize * 2 + 7;
    for (var i = 0; i < total; i++) {
      await repo.create(amountCents: 100 + i, currency: 'EUR', type: 'expense', date: DateTime(2026, 3, 1));
    }

    final seen = <String>[];
    for (var page = 0; page < 3; page++) {
      seen.addAll((await repo.list(page: page)).map((e) => e.id));
    }

    expect(seen.length, total);
    expect(seen.toSet().length, total);
  });

  test('filtering by a parent category matches its whole subtree', () async {
    final all = await db.select(db.categories).get();
    final parent = all.firstWhere((c) => c.parentId == null && all.any((x) => x.parentId == c.id));
    final child = all.firstWhere((c) => c.parentId == parent.id);
    final other = all.firstWhere((c) => c.parentId == null && c.id != parent.id);
    await repo.create(amountCents: 100, currency: 'EUR', type: parent.type, date: DateTime(2026, 3, 1), categoryId: child.id);
    await repo.create(amountCents: 200, currency: 'EUR', type: other.type, date: DateTime(2026, 3, 1), categoryId: other.id);

    final byParent = await repo.listAll(filters: ExpenseFilters(categoryId: parent.id));
    final byChild = await repo.listAll(filters: ExpenseFilters(categoryId: child.id));

    expect(byParent.map((e) => e.amount), [100]);
    expect(byChild.map((e) => e.amount), [100]);
  });
}

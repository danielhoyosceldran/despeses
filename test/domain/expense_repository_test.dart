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
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/dev/perf_seed.dart';
import 'package:despeses/domain/repositories/category_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<int> expenseCount() async =>
      (await db.select(db.expenses).get()).length;

  test('fills an empty database with every transaction type, tags, budgets and templates', () async {
    await seedPerfDatasetIfEmpty(db, CategoryRepository(db), years: 1);

    final expenses = await db.select(db.expenses).get();
    expect(expenses.length, greaterThan(1500));
    expect(expenses.map((e) => e.type).toSet(), {'expense', 'income', 'refund', 'ahorro'});
    expect(await db.select(db.expenseTags).get(), isNotEmpty);
    expect((await db.select(db.budgets).get()).length, 5);
    expect((await db.select(db.recurrings).get()).length, 4);
  });

  test('is a no-op when transactions already exist', () async {
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: 'real',
          amount: 100,
          currency: 'EUR',
          type: 'expense',
          date: DateTime(2026, 1, 1),
        ));

    await seedPerfDatasetIfEmpty(db, CategoryRepository(db), years: 1);

    expect(await expenseCount(), 1);
    expect(await db.select(db.budgets).get(), isEmpty);
  });
}

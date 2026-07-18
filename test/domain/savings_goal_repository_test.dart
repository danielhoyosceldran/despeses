import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/category_repository.dart';
import 'package:despeses/domain/repositories/savings_goal_repository.dart';

const _uuid = Uuid();

void main() {
  late AppDatabase db;
  late CategoryRepository categories;
  late SavingsGoalRepository goals;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    categories = CategoryRepository(db);
    goals = SavingsGoalRepository(db, categories);
  });

  tearDown(() async => db.close());

  Future<String> addSavings({
    required int amount,
    required String categoryId,
    String type = 'ahorro',
    String currency = 'EUR',
    DateTime? date,
  }) async {
    final id = _uuid.v4();
    await db.into(db.expenses).insert(
          ExpensesCompanion.insert(
            id: id,
            amount: amount,
            currency: currency,
            type: type,
            date: date ?? DateTime(2026, 1, 1),
            categoryId: Value(categoryId),
          ),
        );
    return id;
  }

  Future<String> savingsCategory() async {
    return (await categories.listAll()).firstWhere((c) => c.type == 'ahorro').id;
  }

  test('progress sums ahorro under the category and its descendants, ignoring other types', () async {
    final root = await savingsCategory();
    final child = await categories.create(name: 'sub', parentId: root, type: 'ahorro');

    await addSavings(amount: 10000, categoryId: root);
    await addSavings(amount: 5000, categoryId: child);
    // Non-ahorro types under the same category do not count.
    await addSavings(amount: 999, categoryId: root, type: 'expense');
    await addSavings(amount: 888, categoryId: root, type: 'income');

    final id = await goals.create(
      name: 'Japan', categoryId: root, targetCents: 300000, currency: 'EUR');
    final goal = (await goals.byId(id))!;

    final progress = await goals.calculateProgress(goal);
    expect(progress.saved, 15000);
    expect(progress.target, 300000);
    expect(progress.reached, isFalse);
    expect(progress.remaining, 285000);
    expect(progress.monthsLeft, isNull);
    expect(progress.perMonthNeeded, isNull);
  });

  test('savings in a different currency are excluded', () async {
    final root = await savingsCategory();
    await addSavings(amount: 10000, categoryId: root, currency: 'EUR');
    await addSavings(amount: 99999, categoryId: root, currency: 'USD');

    final id = await goals.create(
      name: 'x', categoryId: root, targetCents: 50000, currency: 'EUR');
    final goal = (await goals.byId(id))!;

    expect((await goals.calculateProgress(goal)).saved, 10000);
  });

  test('reached is true once saved meets or exceeds target', () async {
    final root = await savingsCategory();
    await addSavings(amount: 50000, categoryId: root);

    final id = await goals.create(
      name: 'x', categoryId: root, targetCents: 50000, currency: 'EUR');
    final goal = (await goals.byId(id))!;

    final progress = await goals.calculateProgress(goal);
    expect(progress.reached, isTrue);
    expect(progress.ratio, 1.0);
    expect(progress.remaining, 0);
  });

  test('deadline pace divides the remainder across remaining months (incl. current)', () async {
    final root = await savingsCategory();
    await addSavings(amount: 10000, categoryId: root);

    final id = await goals.create(
      name: 'x',
      categoryId: root,
      targetCents: 40000,
      currency: 'EUR',
      deadline: DateTime(2026, 3, 31),
    );
    final goal = (await goals.byId(id))!;

    // From Jan to Mar inclusive = 3 months. Remaining 30000 / 3 = 10000.
    final progress = await goals.calculateProgress(goal, now: DateTime(2026, 1, 15));
    expect(progress.monthsLeft, 3);
    expect(progress.perMonthNeeded, 10000);
  });

  test('past-due goal asks for the whole remainder now', () async {
    final root = await savingsCategory();
    await addSavings(amount: 10000, categoryId: root);

    final id = await goals.create(
      name: 'x',
      categoryId: root,
      targetCents: 40000,
      currency: 'EUR',
      deadline: DateTime(2025, 12, 31),
    );
    final goal = (await goals.byId(id))!;

    final progress = await goals.calculateProgress(goal, now: DateTime(2026, 1, 15));
    expect(progress.monthsLeft, 0);
    expect(progress.perMonthNeeded, 30000);
  });

  test('met goal needs 0 per month regardless of deadline', () async {
    final root = await savingsCategory();
    await addSavings(amount: 50000, categoryId: root);

    final id = await goals.create(
      name: 'x',
      categoryId: root,
      targetCents: 40000,
      currency: 'EUR',
      deadline: DateTime(2026, 6, 30),
    );
    final goal = (await goals.byId(id))!;

    expect((await goals.calculateProgress(goal, now: DateTime(2026, 1, 15))).perMonthNeeded, 0);
  });

  test('update changes name/target/deadline; clearDeadline nulls it', () async {
    final root = await savingsCategory();
    final id = await goals.create(
      name: 'Old',
      categoryId: root,
      targetCents: 10000,
      currency: 'EUR',
      deadline: DateTime(2026, 6, 30),
    );

    await goals.update(id, name: 'New', targetCents: 20000, clearDeadline: true);

    final goal = (await goals.byId(id))!;
    expect(goal.name, 'New');
    expect(goal.targetAmount, 20000);
    expect(goal.deadline, isNull);
    expect(goal.categoryId, root); // locked
  });

  test('deleting the linked category cascades to the goal', () async {
    final root = await savingsCategory();
    final child = await categories.create(name: 'sub', parentId: root, type: 'ahorro');
    final id = await goals.create(
      name: 'x', categoryId: child, targetCents: 10000, currency: 'EUR');

    await categories.delete(child);

    expect(await goals.byId(id), isNull);
  });
}

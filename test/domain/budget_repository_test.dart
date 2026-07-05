import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/budget_repository.dart';
import 'package:despeses/domain/repositories/category_repository.dart';

const _uuid = Uuid();

void main() {
  late AppDatabase db;
  late CategoryRepository categories;
  late BudgetRepository budgets;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    categories = CategoryRepository(db);
    budgets = BudgetRepository(db, categories);
  });

  tearDown(() async => db.close());

  Future<String> addExpense({
    required int amount,
    required String type,
    required DateTime date,
    String? categoryId,
  }) async {
    final id = _uuid.v4();
    await db.into(db.expenses).insert(
          ExpensesCompanion.insert(
            id: id,
            amount: amount,
            currency: 'EUR',
            type: type,
            date: date,
            categoryId: Value(categoryId),
          ),
        );
    return id;
  }

  test('total budget sums expense minus refund, ignores income, recurses into subcategories',
      () async {
    final root = (await categories.listAll()).first;
    final childId = await categories.create(name: 'sub', parentId: root.id);

    await addExpense(amount: 1000, type: 'expense', date: DateTime(2026, 1, 5), categoryId: root.id);
    await addExpense(amount: 500, type: 'expense', date: DateTime(2026, 2, 5), categoryId: childId);
    await addExpense(amount: 200, type: 'refund', date: DateTime(2026, 2, 6), categoryId: childId);
    await addExpense(amount: 9999, type: 'income', date: DateTime(2026, 2, 7), categoryId: root.id);

    final budgetId = await budgets.create(
      name: 'Food total',
      categoryId: root.id,
      amountCents: 5000,
      currency: 'EUR',
      budgetType: 'total',
    );
    final budget = (await budgets.listAll()).firstWhere((b) => b.id == budgetId);

    expect(await budgets.calculateProgress(budget), 1000 + 500 - 200);
  });

  test('range budget only counts expenses within its month window', () async {
    final root = (await categories.listAll()).first;
    await addExpense(amount: 100, type: 'expense', date: DateTime(2026, 1, 15), categoryId: root.id);
    await addExpense(amount: 200, type: 'expense', date: DateTime(2026, 3, 15), categoryId: root.id);
    await addExpense(amount: 300, type: 'expense', date: DateTime(2026, 6, 15), categoryId: root.id);

    final budgetId = await budgets.create(
      name: 'Q1',
      categoryId: root.id,
      amountCents: 1000,
      currency: 'EUR',
      budgetType: 'range',
      startsMonth: '2026-01',
      endsMonth: '2026-03',
    );
    final budget = (await budgets.listAll()).firstWhere((b) => b.id == budgetId);

    expect(await budgets.calculateProgress(budget), 300);
  });

  test('months budget only counts expenses in the selected months', () async {
    final root = (await categories.listAll()).first;
    await addExpense(amount: 100, type: 'expense', date: DateTime(2026, 1, 15), categoryId: root.id);
    await addExpense(amount: 200, type: 'expense', date: DateTime(2026, 2, 15), categoryId: root.id);
    await addExpense(amount: 300, type: 'expense', date: DateTime(2026, 12, 15), categoryId: root.id);

    final budgetId = await budgets.create(
      name: 'Winter',
      categoryId: root.id,
      amountCents: 1000,
      currency: 'EUR',
      budgetType: 'months',
      months: const [BudgetMonth(2026, 1), BudgetMonth(2026, 12)],
    );
    final budget = (await budgets.listAll()).firstWhere((b) => b.id == budgetId);

    expect(await budgets.calculateProgress(budget), 400);
  });

  test('create rejects zero or multiple dimensions set', () async {
    final root = (await categories.listAll()).first;
    expect(
      () => budgets.create(name: 'x', amountCents: 100, currency: 'EUR', budgetType: 'total'),
      throwsArgumentError,
    );
    expect(
      () => budgets.create(
        name: 'x',
        categoryId: root.id,
        tagId: 'whatever',
        amountCents: 100,
        currency: 'EUR',
        budgetType: 'total',
      ),
      throwsArgumentError,
    );
  });

  test('updateNameAndAmount only touches name/amount, never the dimension (locked in edit, plan §3.2)', () async {
    final root = (await categories.listAll()).first;
    final id = await budgets.create(
      name: 'Original',
      categoryId: root.id,
      amountCents: 1000,
      currency: 'EUR',
      budgetType: 'total',
    );

    await budgets.updateNameAndAmount(id, name: 'Renamed', amountCents: 2000);

    final updated = (await budgets.listAll()).firstWhere((b) => b.id == id);
    expect(updated.name, 'Renamed');
    expect(updated.amount, 2000);
    expect(updated.categoryId, root.id);
    expect(updated.budgetType, 'total');
  });

  test('total budgets are always active regardless of navigated month (web divergence)', () {
    final fakeBudget = Budget(
      id: 'x',
      name: 'x',
      amount: 100,
      currency: 'EUR',
      budgetType: 'total',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(budgets.isActiveForMonth(fakeBudget, '2020-01'), isTrue);
    expect(budgets.isActiveForMonth(fakeBudget, '2099-12'), isTrue);
  });
}

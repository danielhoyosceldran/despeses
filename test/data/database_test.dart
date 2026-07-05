import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/data/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('seed creates default reference data', () async {
    final profile = await db.select(db.profile).getSingle();
    expect(profile.currency, 'EUR');
    expect(profile.language, 'en');

    final tagGroups = await db.select(db.tagGroups).get();
    expect(tagGroups.map((g) => g.name), containsAll([
      'tag_group.ungrouped',
      'tag_group.social_context',
      'tag_group.motivation',
      'tag_group.life_moment',
    ]));

    final tags = await db.select(db.tags).get();
    expect(tags.length, 14);
    expect(tags.every((t) => t.isDefault), isTrue);

    final categories = await db.select(db.categories).get();
    expect(categories.length, 7);
    expect(categories.every((c) => c.parentId == null), isTrue);

    final paymentMethods = await db.select(db.paymentMethods).get();
    expect(paymentMethods.length, 4);
  });

  test('expense currency is frozen at insert and never changed by app logic', () async {
    final category = (await db.select(db.categories).get()).first;
    const id = 'exp-1';
    await db.into(db.expenses).insert(
          ExpensesCompanion.insert(
            id: id,
            amount: 1500,
            currency: 'EUR',
            type: 'expense',
            date: DateTime(2026, 7, 1),
            categoryId: Value(category.id),
          ),
        );

    final stored = await (db.select(db.expenses)
          ..where((e) => e.id.equals(id)))
        .getSingle();
    expect(stored.currency, 'EUR');

    // Updating other fields must not touch currency; the app never exposes
    // a way to change it (immutability is enforced by omission, not by DB trigger).
    await (db.update(db.expenses)..where((e) => e.id.equals(id))).write(
      const ExpensesCompanion(description: Value('updated')),
    );
    final afterUpdate = await (db.select(db.expenses)
          ..where((e) => e.id.equals(id)))
        .getSingle();
    expect(afterUpdate.currency, 'EUR');
    expect(afterUpdate.description, 'updated');
  });

  test('deleting a category cascades to subcategories and sets expense.categoryId null', () async {
    final root = (await db.select(db.categories).get()).first;
    const childId = 'cat-child';
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: childId,
            parentId: Value(root.id),
            name: 'child',
          ),
        );

    const expenseId = 'exp-2';
    await db.into(db.expenses).insert(
          ExpensesCompanion.insert(
            id: expenseId,
            amount: 100,
            currency: 'EUR',
            type: 'expense',
            date: DateTime(2026, 7, 1),
            categoryId: Value(root.id),
          ),
        );

    await (db.delete(db.categories)..where((c) => c.id.equals(root.id))).go();

    final remainingChild = await (db.select(db.categories)
          ..where((c) => c.id.equals(childId)))
        .getSingleOrNull();
    expect(remainingChild, isNull);

    final expense =
        await (db.select(db.expenses)..where((e) => e.id.equals(expenseId)))
            .getSingle();
    expect(expense.categoryId, isNull);
  });
}

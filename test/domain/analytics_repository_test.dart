import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/analytics_repository.dart';
import 'package:despeses/domain/repositories/category_repository.dart';

const _uuid = Uuid();

void main() {
  late AppDatabase db;
  late CategoryRepository categories;
  late AnalyticsRepository analytics;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    categories = CategoryRepository(db);
    analytics = AnalyticsRepository(db, categories);
  });

  tearDown(() async => db.close());

  Future<void> addExpense({
    required int amount,
    required String type,
    required DateTime date,
    String? categoryId,
    List<String> tagIds = const [],
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
    for (final tagId in tagIds) {
      await db.into(db.expenseTags).insert(ExpenseTagsCompanion.insert(expenseId: id, tagId: tagId));
    }
  }

  test('monthTotal excludes income and subtracts refunds', () async {
    final month = DateTime(2026, 3);
    await addExpense(amount: 1000, type: 'expense', date: DateTime(2026, 3, 5));
    await addExpense(amount: 200, type: 'refund', date: DateTime(2026, 3, 6));
    await addExpense(amount: 5000, type: 'income', date: DateTime(2026, 3, 7));
    await addExpense(amount: 999, type: 'expense', date: DateTime(2026, 4, 1)); // different month

    expect(await analytics.monthTotal(month, 'EUR'), 800);
  });

  test('root category breakdown aggregates subcategory spend into the root slice', () async {
    final root = (await categories.listAll()).first;
    final child = await categories.create(name: 'sub', parentId: root.id);
    final month = DateTime(2026, 3);

    await addExpense(amount: 300, type: 'expense', date: DateTime(2026, 3, 1), categoryId: root.id);
    await addExpense(amount: 700, type: 'expense', date: DateTime(2026, 3, 2), categoryId: child);

    final rootSlices = await analytics.categoryBreakdown(month, null, 'EUR');
    final rootSlice = rootSlices.firstWhere((s) => s.categoryId == root.id);
    expect(rootSlice.amountCents, 1000); // 300 direct + 700 from subcategory
    expect(rootSlice.isDirect, isFalse);
  });

  test('drilling into a category splits its own "direct" spend from its children', () async {
    final root = (await categories.listAll()).first;
    final child = await categories.create(name: 'sub', parentId: root.id);
    final month = DateTime(2026, 3);

    await addExpense(amount: 300, type: 'expense', date: DateTime(2026, 3, 1), categoryId: root.id);
    await addExpense(amount: 700, type: 'expense', date: DateTime(2026, 3, 2), categoryId: child);

    final childLevel = await analytics.categoryBreakdown(month, root.id, 'EUR');

    final childSlice = childLevel.firstWhere((s) => s.categoryId == child && !s.isDirect);
    expect(childSlice.amountCents, 700);

    final directSlice = childLevel.firstWhere((s) => s.isDirect);
    expect(directSlice.amountCents, 300);
    expect(directSlice.categoryId, root.id);

    // Sum of children + direct == the root's own aggregate slice from the level above.
    expect(childSlice.amountCents + directSlice.amountCents, 1000);
  });

  test('tag breakdown lets a multi-tag expense count in each of its tags', () async {
    final tags = await db.select(db.tags).get();
    final tagA = tags[0].id;
    final tagB = tags[1].id;
    final month = DateTime(2026, 3);

    await addExpense(amount: 500, type: 'expense', date: DateTime(2026, 3, 1), tagIds: [tagA, tagB]);

    final slices = await analytics.tagBreakdown(month, 'EUR');
    final byId = {for (final s in slices) s.tagId: s.amountCents};
    expect(byId[tagA], 500);
    expect(byId[tagB], 500); // counted twice in total — expected divergence (plan §3.6)
  });
}

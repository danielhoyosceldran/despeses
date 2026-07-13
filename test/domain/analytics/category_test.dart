import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/analytics/analytics_category.dart';
import 'package:despeses/domain/repositories/analytics/analytics_math.dart';
import 'package:despeses/domain/repositories/category_repository.dart';

const _uuid = Uuid();

void main() {
  late AppDatabase db;
  late CategoryRepository categories;
  late CategoryAnalytics analytics;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    categories = CategoryRepository(db);
    analytics = CategoryAnalytics(db, categories);
  });
  tearDown(() async => db.close());

  Future<void> add(int amount, String type, DateTime date, {String? categoryId}) async {
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: _uuid.v4(),
          amount: amount,
          currency: 'EUR',
          type: type,
          date: date,
          categoryId: Value(categoryId),
        ));
  }

  final march = DateRange.month(DateTime(2026, 3));

  test('root breakdown aggregates a leaf subcategory into its root slice', () async {
    final root = (await categories.listChildren(null, type: 'expense')).first;
    final child = await categories.create(name: 'sub', parentId: root.id); // inherits expense type

    await add(700, 'expense', DateTime(2026, 3, 2), categoryId: child);

    final roots = await analytics.breakdown(march, type: 'expense', currency: 'EUR');
    final slice = roots.firstWhere((s) => s.categoryId == root.id);
    expect(slice.amountCents, 700);
  });

  test('breakdown is per-type: income transactions never leak into the expense tree', () async {
    final expenseRoot = (await categories.listChildren(null, type: 'expense')).first;
    final incomeRoot = (await categories.listChildren(null, type: 'income')).first;

    await add(1000, 'expense', DateTime(2026, 3, 1), categoryId: expenseRoot.id);
    await add(5000, 'income', DateTime(2026, 3, 1), categoryId: incomeRoot.id);

    final expenseSlices = await analytics.breakdown(march, type: 'expense', currency: 'EUR');
    expect(expenseSlices.map((s) => s.categoryId), isNot(contains(incomeRoot.id)));
    expect(expenseSlices.firstWhere((s) => s.categoryId == expenseRoot.id).amountCents, 1000);

    final incomeSlices = await analytics.breakdown(march, type: 'income', currency: 'EUR');
    expect(incomeSlices.single.categoryId, incomeRoot.id);
    expect(incomeSlices.single.amountCents, 5000);
  });

  test('ranking returns shares that sum to 1 and a correct average ticket', () async {
    final roots = await categories.listChildren(null, type: 'expense');
    await add(300, 'expense', DateTime(2026, 3, 1), categoryId: roots[0].id);
    await add(100, 'expense', DateTime(2026, 3, 2), categoryId: roots[0].id);
    await add(200, 'expense', DateTime(2026, 3, 3), categoryId: roots[1].id);

    final ranking = await analytics.ranking(march, type: 'expense', currency: 'EUR');
    expect(ranking.first.categoryId, roots[0].id); // 400 > 200
    expect(ranking.first.amountCents, 400);
    expect(ranking.first.averageTicketCents, 200); // 400 / 2 txns
    expect(ranking.map((e) => e.share).reduce((a, b) => a + b), closeTo(1.0, 1e-9));
  });
}

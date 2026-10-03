import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/dev/perf_seed.dart';
import 'package:despeses/domain/repositories/analytics/analytics_budgets.dart';
import 'package:despeses/domain/repositories/analytics/analytics_category.dart';
import 'package:despeses/domain/repositories/analytics/analytics_dashboard.dart';
import 'package:despeses/domain/repositories/analytics/analytics_math.dart';
import 'package:despeses/domain/repositories/analytics/analytics_query.dart';
import 'package:despeses/domain/repositories/analytics/analytics_tags.dart';
import 'package:despeses/domain/repositories/analytics/analytics_timeseries.dart';
import 'package:despeses/domain/repositories/budget_repository.dart';
import 'package:despeses/domain/repositories/category_repository.dart';

/// The SQL aggregates (BL-062) and the batched budget progress (BL-063) must
/// give exactly what the previous row-by-row Dart computations gave. These
/// tests recompute every figure from full rows (the reference) over the
/// profiling dataset and compare.
void main() {
  late AppDatabase db;
  late CategoryRepository categories;
  late BudgetRepository budgets;
  const currency = 'EUR';
  final now = DateTime.now();
  final month = DateTime(now.year, now.month);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    categories = CategoryRepository(db);
    budgets = BudgetRepository(db, categories);
    await seedPerfDatasetIfEmpty(db, categories, years: 1);
  });

  tearDown(() async => db.close());

  Future<List<Expense>> rows(DateRange range) => expensesInRange(db, range, currency);

  test('monthly spent totals match the row-based outflow', () async {
    final range = DateRange.trailingMonths(month, 12);
    final totals = await TimeseriesAnalytics(db).monthlyTotals(range, currency);
    final all = await rows(range);
    expect(totals, hasLength(12));
    for (final (m, cents) in totals) {
      final inMonth = all.where((e) => e.date.year == m.year && e.date.month == m.month);
      expect(cents, expenseOutflow(inMonth), reason: '$m');
    }
    expect(totals.map((t) => t.$2).reduce((a, b) => a + b), expenseOutflow(all));
  });

  test('per-day heat matches the row-based sum', () async {
    final previous = DateTime(month.year, month.month - 1);
    final heat = await TimeseriesAnalytics(db).calendarHeat(previous, currency);
    final all = (await rows(DateRange.month(previous))).where((e) => spendTypes.contains(e.type));
    final expected = <int, int>{};
    for (final e in all) {
      expected[e.date.day] = (expected[e.date.day] ?? 0) + signedAmountOf(e);
    }
    expect(heat, expected);
  });

  test('category breakdown matches the row-based roll-up', () async {
    final range = DateRange.trailingMonths(month, 6);
    final slices = await CategoryAnalytics(db, categories).breakdown(range, type: 'expense', currency: currency);
    final expenses = (await rows(range)).where((e) => e.type == 'expense').toList();
    final descendants = await categories.descendantMap();
    for (final s in slices) {
      final ids = {s.categoryId, ...?descendants[s.categoryId]};
      final matching = expenses.where((e) => ids.contains(e.categoryId));
      expect(s.amountCents, matching.fold<int>(0, (sum, e) => sum + e.amount));
      expect(s.count, matching.length);
    }
    expect(slices.fold<int>(0, (sum, s) => sum + s.amountCents), sumOfType(expenses, 'expense'));
  });

  test('tag slices match the row-based tag grouping', () async {
    final range = DateRange.trailingMonths(month, 6);
    final slices = await TagAnalytics(db).byTag(range, currency);
    final all = await rows(range);
    final byId = {for (final e in all) e.id: e};
    final links = await db.select(db.expenseTags).get();
    final grouped = <String, List<Expense>>{};
    for (final l in links) {
      final e = byId[l.expenseId];
      if (e != null) grouped.putIfAbsent(l.tagId, () => []).add(e);
    }
    expect(slices, isNotEmpty);
    for (final s in slices) {
      expect(s.amountCents, expenseOutflow(grouped[s.tagId]!));
      expect(s.savingsCents, savingsSetAside(grouped[s.tagId]!));
      expect(s.count, grouped[s.tagId]!.length);
    }
    expect(slices.length, grouped.values.where((g) => expenseOutflow(g) != 0).length);
  });

  test('batched budget progress matches one row-based computation per budget', () async {
    // Add project/event budgets next to the seeded category/tag/range ones.
    final projectId = const Uuid().v4();
    final eventId = const Uuid().v4();
    await db.into(db.projects).insert(ProjectsCompanion.insert(id: projectId, name: 'P'));
    await db.into(db.events).insert(EventsCompanion.insert(id: eventId, name: 'E'));
    final some = (await rows(DateRange.trailingMonths(month, 3))).take(40).toList();
    for (var i = 0; i < some.length; i++) {
      await (db.update(db.expenses)..where((e) => e.id.equals(some[i].id))).write(
        i.isEven ? ExpensesCompanion(projectId: Value(projectId)) : ExpensesCompanion(eventId: Value(eventId)),
      );
    }
    await budgets.create(name: 'p', projectId: projectId, amountCents: 1, currency: currency, budgetType: 'monthly');
    await budgets.create(name: 'e', eventId: eventId, amountCents: 1, currency: currency, budgetType: 'monthly');

    final all = await budgets.listAll();
    expect(all.length, greaterThanOrEqualTo(5));
    final descendants = await categories.descendantMap();
    final links = await db.select(db.expenseTags).get();

    for (final inMonth in [month, DateTime(month.year, month.month - 2, 10)]) {
      final batched = await budgets.progressFor(all, inMonth: inMonth);
      for (final b in all) {
        final (start, end) = switch (b.budgetType) {
          'range' => (
              DateTime(int.parse(b.startsMonth!.split('-')[0]), int.parse(b.startsMonth!.split('-')[1])),
              DateTime(int.parse(b.endsMonth!.split('-')[0]), int.parse(b.endsMonth!.split('-')[1]) + 1),
            ),
          _ => (DateTime(inMonth.year, inMonth.month), DateTime(inMonth.year, inMonth.month + 1)),
        };
        final inWindow = (await expensesInRange(db, DateRange(start, end.subtract(const Duration(seconds: 1))), b.currency))
            .where((e) => spendTypes.contains(e.type));
        final Iterable<Expense> matching;
        if (b.categoryId != null) {
          final ids = {b.categoryId!, ...?descendants[b.categoryId!]};
          matching = inWindow.where((e) => ids.contains(e.categoryId));
        } else if (b.projectId != null) {
          matching = inWindow.where((e) => e.projectId == b.projectId);
        } else if (b.eventId != null) {
          matching = inWindow.where((e) => e.eventId == b.eventId);
        } else {
          final tagged = {for (final l in links) if (l.tagId == b.tagId) l.expenseId};
          matching = inWindow.where((e) => tagged.contains(e.id));
        }
        expect(batched[b.id], expenseOutflow(matching), reason: '${b.name} @ $inMonth');
        expect(await budgets.calculateProgress(b, inMonth: inMonth), batched[b.id]);
      }
    }
  });

  test('watchMonthProgress re-emits after a write', () async {
    final stream = budgets.watchMonthProgress(month);
    final first = await stream.first;
    expect(first.budgets, isNotEmpty);

    final emissions = <BudgetMonthProgress>[];
    final sub = stream.listen(emissions.add);
    await pumpEventQueue();
    final category = first.budgets.firstWhere((b) => b.categoryId != null && b.budgetType == 'monthly');
    final before = first.spent[category.id]!;
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: const Uuid().v4(),
          amount: 1234,
          currency: currency,
          type: 'expense',
          date: DateTime(now.year, now.month, now.day),
          categoryId: Value(category.categoryId),
        ));
    await pumpEventQueue();
    await sub.cancel();
    expect(emissions.last.spent[category.id], before + 1234);
  });

  test('summary KPIs match the per-metric calculators', () async {
    final budgetAnalytics = BudgetAnalytics(budgets);
    final category = CategoryAnalytics(db, categories);
    final health = await DashboardAnalytics(db, category, budgetAnalytics, budgets).summary(month, currency);
    final timeseries = TimeseriesAnalytics(db);

    final trailing = await timeseries.monthlyTotals(DateRange.trailingMonths(month, 3), currency);
    expect(health.spendThisMonth, trailing.last.$2);
    expect(health.averageSpend3M, mean(trailing.map((t) => t.$2)));
    final ranking = await category.ranking(DateRange.month(month), type: 'expense', currency: currency);
    expect(health.topCategoryId, ranking.isEmpty ? null : ranking.first.categoryId);
    expect(health.projectedSpend, await timeseries.endOfMonthProjection(month, currency));

    final active = (await budgets.listAll()).where((b) => budgets.isActiveForMonth(b, monthKeyOf(month)));
    var atRisk = 0;
    for (final b in active) {
      final pace = await budgetAnalytics.pace(b);
      if (pace.overPace || pace.spentFraction > 1) atRisk++;
    }
    expect(health.budgetsAtRisk, atRisk);
  });
}

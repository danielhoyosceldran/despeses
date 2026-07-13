import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/analytics/analytics_budgets.dart';
import 'package:despeses/domain/repositories/analytics/analytics_events.dart';
import 'package:despeses/domain/repositories/budget_repository.dart';
import 'package:despeses/domain/repositories/category_repository.dart';

const _uuid = Uuid();

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> add(int amount, String type, DateTime date, {String? eventId, String? categoryId}) async {
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: _uuid.v4(),
          amount: amount,
          currency: 'EUR',
          type: type,
          date: date,
          eventId: Value(eventId),
          categoryId: Value(categoryId),
        ));
  }

  group('events', () {
    test('totalCost, costPerDay and outOfRange', () async {
      const eventId = 'ev1';
      final start = DateTime(2026, 6, 1);
      final end = DateTime(2026, 6, 5);
      await db.into(db.events).insert(EventsCompanion.insert(
            id: eventId,
            name: 'Trip',
            startsAt: Value(start),
            endsAt: Value(end),
          ));
      await add(600, 'expense', DateTime(2026, 6, 2), eventId: eventId);
      await add(200, 'expense', DateTime(2026, 6, 4), eventId: eventId);
      await add(100, 'expense', DateTime(2026, 6, 20), eventId: eventId); // out of range

      final ev = EventAnalytics(db);
      expect(await ev.totalCost(eventId: eventId), 900);
      // 900 / 5 days = 180.
      expect(await ev.costPerDay(startsAt: start, endsAt: end, eventId: eventId), closeTo(180, 1e-9));
      final oor = await ev.outOfRange(eventId: eventId, startsAt: start, endsAt: end);
      expect(oor.length, 1);
      expect(oor.single.amount, 100);
    });
  });

  group('budgets', () {
    test('pace flags over-spending relative to elapsed time and projects the close', () async {
      final categories = CategoryRepository(db);
      final budgets = BudgetRepository(db, categories);
      final root = (await categories.listChildren(null, type: 'expense')).first;

      // 2-month range budget (Mar–Apr), limit 1000. By mid-March (month 1 of 2)
      // 600 already spent → spent 60% while only 50% of the period elapsed.
      final id = await budgets.create(
        name: 'food',
        categoryId: root.id,
        amountCents: 1000,
        currency: 'EUR',
        budgetType: 'range',
        startsMonth: '2026-03',
        endsMonth: '2026-04',
      );
      await add(600, 'expense', DateTime(2026, 3, 10), categoryId: root.id);
      final budget = (await budgets.listAll()).firstWhere((b) => b.id == id);

      final analytics = BudgetAnalytics(budgets);
      final pace = await analytics.pace(budget, asOf: DateTime(2026, 3, 15));
      expect(pace.spentCents, 600);
      expect(pace.limitCents, 1000);
      expect(pace.timeFraction, closeTo(0.5, 1e-9)); // month 1 of 2
      expect(pace.overPace, isTrue); // 0.6 spent > 0.5 elapsed
      expect(pace.projectedEndCents, 1200); // 600 / 0.5
    });
  });
}

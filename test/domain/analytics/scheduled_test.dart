import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/analytics/analytics_events.dart';
import 'package:despeses/domain/repositories/analytics/analytics_math.dart';
import 'package:despeses/domain/repositories/analytics/analytics_query.dart';

const _uuid = Uuid();

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> add(int amount, DateTime date, {String? eventId}) => db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: _uuid.v4(),
          amount: amount,
          currency: 'EUR',
          type: 'expense',
          date: date,
          eventId: Value(eventId),
        ),
      );

  test('isScheduled is day-level: later today is not scheduled, tomorrow is', () {
    final now = DateTime(2026, 3, 10, 9);
    Expense at(DateTime d) => Expense(
          id: 'x',
          amount: 1,
          currency: 'EUR',
          type: 'expense',
          date: d,
          createdAt: now,
          updatedAt: now,
        );

    expect(isScheduled(at(DateTime(2026, 3, 10, 23, 59)), now: now), isFalse);
    expect(isScheduled(at(DateTime(2026, 3, 11)), now: now), isTrue);
    expect(isScheduled(at(DateTime(2026, 3, 9)), now: now), isFalse);
  });

  test('analytics queries leave out future-dated transactions until their day', () async {
    final today = DateTime.now();
    await add(100, today);
    await add(900, today.add(const Duration(days: 3)));
    final range = DateRange(today.subtract(const Duration(days: 10)), today.add(const Duration(days: 10)));

    final rows = await expensesInRange(db, range, 'EUR');

    expect(rows.map((e) => e.amount), [100]);
  });

  test('event totals leave out future-dated transactions', () async {
    await db.into(db.events).insert(EventsCompanion.insert(id: 'ev', name: 'Trip'));
    final today = DateTime.now();
    await add(100, today, eventId: 'ev');
    await add(900, today.add(const Duration(days: 3)), eventId: 'ev');

    expect(await EventAnalytics(db).totalCost(eventId: 'ev'), 100);
  });
}

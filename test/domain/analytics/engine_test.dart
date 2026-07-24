import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/analytics/analytics_behavior.dart';
import 'package:despeses/domain/repositories/analytics/analytics_math.dart';
import 'package:despeses/domain/repositories/analytics/analytics_payment.dart';
import 'package:despeses/domain/repositories/analytics/analytics_tags.dart';
import 'package:despeses/domain/repositories/analytics/analytics_timeseries.dart';

const _uuid = Uuid();

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> add(
    int amount,
    String type,
    DateTime date, {
    String? paymentMethodId,
    String? categoryId,
    List<String> tagIds = const [],
  }) async {
    final id = _uuid.v4();
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: id,
          amount: amount,
          currency: 'EUR',
          type: type,
          date: date,
          paymentMethodId: Value(paymentMethodId),
          categoryId: Value(categoryId),
        ));
    for (final t in tagIds) {
      await db.into(db.expenseTags).insert(ExpenseTagsCompanion.insert(expenseId: id, tagId: t));
    }
  }

  group('timeseries', () {
    test('monthlyTotals is signed spend per month over the window', () async {
      await add(1000, 'expense', DateTime(2026, 2, 5));
      await add(300, 'expense', DateTime(2026, 3, 5));
      await add(100, 'refund', DateTime(2026, 3, 6));
      final ts = TimeseriesAnalytics(db);
      final totals = await ts.monthlyTotals(DateRange.trailingMonths(DateTime(2026, 3), 3), 'EUR');
      expect(totals.map((e) => e.$2).toList(), [0, 1000, 200]); // Jan, Feb, Mar
    });

    test('monthlyTotals excludes ahorro and income (pure expense outflow)', () async {
      await add(5000, 'income', DateTime(2026, 3, 1));
      await add(1000, 'expense', DateTime(2026, 3, 5));
      await add(200, 'refund', DateTime(2026, 3, 6));
      await add(800, 'ahorro', DateTime(2026, 3, 7));
      final ts = TimeseriesAnalytics(db);
      final totals = await ts.monthlyTotals(DateRange.month(DateTime(2026, 3)), 'EUR');
      expect(totals.single.$2, 800); // 1000 expense - 200 refund; ahorro/income excluded
    });

    test('momYoY compares current vs previous month and same month last year', () async {
      await add(500, 'expense', DateTime(2025, 3, 1)); // last year
      await add(200, 'expense', DateTime(2026, 2, 1)); // prev month
      await add(400, 'expense', DateTime(2026, 3, 1)); // current
      final ts = TimeseriesAnalytics(db);
      final r = await ts.momYoY(DateTime(2026, 3), 'EUR');
      expect(r.mom.absolute, 200); // 400 - 200
      expect(r.yoy.absolute, -100); // 400 - 500
      expect(r.mom.fraction, closeTo(1.0, 1e-9)); // +100%
    });

    test('endOfMonthProjection extrapolates the daily pace', () async {
      await add(1000, 'expense', DateTime(2026, 3, 1));
      final ts = TimeseriesAnalytics(db);
      // As of day 10 of a 31-day month: pace 100/day → ~3100.
      final proj = await ts.endOfMonthProjection(DateTime(2026, 3), 'EUR', asOf: DateTime(2026, 3, 10));
      expect(proj, 3100);
    });
  });

  group('behavior', () {
    test('ticketStats returns mean, median and max of expense amounts', () async {
      await add(100, 'expense', DateTime(2026, 3, 1));
      await add(300, 'expense', DateTime(2026, 3, 2));
      await add(200, 'expense', DateTime(2026, 3, 3));
      final b = BehaviorAnalytics(db);
      final s = await b.ticketStats(DateRange.month(DateTime(2026, 3)), 'EUR');
      expect(s.mean, closeTo(200, 1e-9));
      expect(s.median, 200);
      expect(s.max, 300);
      expect(s.count, 3);
    });

    test('noSpendDays counts empty days and the trailing streak', () async {
      await add(100, 'expense', DateTime(2026, 3, 1));
      await add(100, 'expense', DateTime(2026, 3, 2));
      final b = BehaviorAnalytics(db);
      // As of day 5: days 3,4,5 had no spend → 3 no-spend days, streak 3.
      final r = await b.noSpendDays(DateTime(2026, 3), 'EUR', asOf: DateTime(2026, 3, 5));
      expect(r.noSpendDays, 3);
      expect(r.currentStreak, 3);
    });

    test('refunds summarises total refunded and ratio to gross spend', () async {
      await add(1000, 'expense', DateTime(2026, 3, 1));
      await add(250, 'refund', DateTime(2026, 3, 2));
      final b = BehaviorAnalytics(db);
      final r = await b.refunds(DateRange.month(DateTime(2026, 3)), 'EUR');
      expect(r.totalRefunded, 250);
      expect(r.grossSpend, 1000);
      expect(r.ratio, closeTo(0.25, 1e-9));
    });
  });

  group('payment', () {
    test('byMethod and share split spend across methods', () async {
      await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(id: 'cash', name: 'Cash'));
      await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(id: 'card', name: 'Card'));
      await add(600, 'expense', DateTime(2026, 3, 1), paymentMethodId: 'cash');
      await add(400, 'expense', DateTime(2026, 3, 2), paymentMethodId: 'card');
      final p = PaymentAnalytics(db);
      final by = await p.byMethod(DateRange.month(DateTime(2026, 3)), 'EUR');
      expect(by['cash'], 600);
      expect(by['card'], 400);
      expect(await p.share(DateRange.month(DateTime(2026, 3)), 'EUR', 'cash'), closeTo(0.6, 1e-9));
    });
  });

  group('tags', () {
    test('coverageGap is the fraction of untagged spend transactions', () async {
      final tags = await db.select(db.tags).get();
      await add(100, 'expense', DateTime(2026, 3, 1), tagIds: [tags.first.id]);
      await add(100, 'expense', DateTime(2026, 3, 2)); // untagged
      final t = TagAnalytics(db);
      expect(await t.coverageGap(DateRange.month(DateTime(2026, 3)), 'EUR'), closeTo(0.5, 1e-9));
    });

    test('byTag counts a multi-tag expense fully in each tag', () async {
      final tags = await db.select(db.tags).get();
      await add(500, 'expense', DateTime(2026, 3, 1), tagIds: [tags[0].id, tags[1].id]);
      final t = TagAnalytics(db);
      final slices = await t.byTag(DateRange.month(DateTime(2026, 3)), 'EUR');
      final byId = {for (final s in slices) s.tagId: s.amountCents};
      expect(byId[tags[0].id], 500);
      expect(byId[tags[1].id], 500);
    });
  });
}

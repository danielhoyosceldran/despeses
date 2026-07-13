import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/analytics/analytics_cashflow.dart';
import 'package:despeses/domain/repositories/analytics/analytics_math.dart';

const _uuid = Uuid();

void main() {
  late AppDatabase db;
  late CashflowAnalytics cashflow;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cashflow = CashflowAnalytics(db);
  });
  tearDown(() async => db.close());

  Future<void> add(int amount, String type, DateTime date) async {
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: _uuid.v4(),
          amount: amount,
          currency: 'EUR',
          type: type,
          date: date,
        ));
  }

  test('monthly cash-flow: net = income - spend - savings, savings excluded from spend', () async {
    await add(5000, 'income', DateTime(2026, 3, 5));
    await add(1000, 'expense', DateTime(2026, 3, 6));
    await add(200, 'refund', DateTime(2026, 3, 7));
    await add(800, 'ahorro', DateTime(2026, 3, 8));

    final rows = await cashflow.monthly(DateRange.month(DateTime(2026, 3)), 'EUR');
    expect(rows.length, 1);
    final m = rows.first;
    expect(m.income, 5000);
    expect(m.spend, 800); // 1000 expense - 200 refund; ahorro NOT counted as spend
    expect(m.savings, 800);
    expect(m.net, 3400); // 5000 - 800 - 800
    expect(m.savingsRate, closeTo(0.16, 1e-9)); // 800 / 5000
  });

  test('cumulative savings runs a running total across months', () async {
    await add(300, 'ahorro', DateTime(2026, 1, 10));
    await add(500, 'ahorro', DateTime(2026, 2, 10));
    await add(200, 'ahorro', DateTime(2026, 3, 10));

    final series = await cashflow.cumulativeSavings(
      DateRange.trailingMonths(DateTime(2026, 3), 3),
      'EUR',
    );
    expect(series.map((e) => e.$2).toList(), [300, 800, 1000]);
  });

  test('savingsRate is 0 when there is no income', () async {
    await add(800, 'ahorro', DateTime(2026, 3, 8));
    expect(await cashflow.savingsRate(DateTime(2026, 3), 'EUR'), 0);
  });
}

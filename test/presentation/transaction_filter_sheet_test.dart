import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despeses/core/providers/app_providers.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/main.dart';
import 'package:despeses/presentation/screens/expenses_screen.dart';

/// Transactions tab: the advanced filter sheet. Kept in its own file
/// (isolate): opening the sheet awaits `translationsProvider.future`, which
/// never resolved when this ran after another app test in the same isolate.
void main() {
  late AppDatabase db;

  Future<void> insertExpense(String id, DateTime date, int amount, String description) =>
      db.into(db.expenses).insert(ExpensesCompanion.insert(
            id: id,
            amount: amount,
            currency: 'EUR',
            type: 'expense',
            date: date,
            description: Value(description),
          ));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    await insertExpense('a', DateTime(now.year, now.month, 1, 9), 1234, 'Café Plaza');
    await insertExpense('b', DateTime(now.year, now.month, 1, 10), 5000, 'Supermarket');
    await insertExpense('c', DateTime(now.year - 1, 6, 15), 999, 'Old cafe');
  });

  tearDown(() async => db.close());

  testWidgets('filter sheet multi-selects types and amount range', (tester) async {
    final now = DateTime.now();
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: 'i',
          amount: 300000,
          currency: 'EUR',
          type: 'income',
          date: DateTime(now.year, now.month, 1, 11),
          description: const Value('Salary'),
        ));
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const DespesesApp(),
    ));
    await settle(tester);
    await tester.tap(find.text('Transactions').first);
    await settle(tester);
    final screen = find.byType(ExpensesScreen);
    Finder inScreen(String text) => find.descendant(of: screen, matching: find.text(text));

    await tester.tap(find.byTooltip('Filter'));
    await settle(tester);
    // The sheet opens after loading the catalogs: pump until it's there.
    for (var i = 0; i < 50 && find.text('Filters').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Type'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Expense'));
    await tester.tap(find.widgetWithText(FilterChip, 'Income'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Min amount'), '20');
    await tester.tap(find.text('Apply'));
    await settle(tester);

    expect(inScreen('Salary'), findsOneWidget);
    expect(inScreen('Supermarket'), findsOneWidget);
    expect(inScreen('Café Plaza'), findsNothing, reason: 'below the minimum amount');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

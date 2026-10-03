import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despeses/core/providers/app_providers.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/main.dart';
import 'package:despeses/presentation/screens/expenses_screen.dart';

/// Transactions tab: opens on the current month, the "This month" chip lifts
/// the date range, and the search box narrows the list.
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

  testWidgets('this-month default, chip toggle and search', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const DespesesApp(),
    ));
    await settle(tester);

    await tester.tap(find.text('Transactions').first);
    await settle(tester);
    final screen = find.byType(ExpensesScreen);
    Finder inScreen(String text) => find.descendant(of: screen, matching: find.text(text));

    expect(inScreen('Café Plaza'), findsOneWidget);
    expect(inScreen('Supermarket'), findsOneWidget);
    expect(inScreen('Old cafe'), findsNothing, reason: 'opens limited to the current month');

    await tester.tap(find.descendant(of: screen, matching: find.byType(FilterChip)));
    await settle(tester);
    expect(inScreen('Old cafe'), findsOneWidget, reason: 'chip off lists every month');

    await tester.enterText(find.descendant(of: screen, matching: find.byType(TextField)), 'cafe');
    await settle(tester);
    expect(inScreen('Café Plaza'), findsOneWidget);
    expect(inScreen('Old cafe'), findsOneWidget);
    expect(inScreen('Supermarket'), findsNothing);

    await tester.enterText(find.descendant(of: screen, matching: find.byType(TextField)), '>20');
    await settle(tester);
    expect(inScreen('Supermarket'), findsOneWidget);
    expect(inScreen('Café Plaza'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

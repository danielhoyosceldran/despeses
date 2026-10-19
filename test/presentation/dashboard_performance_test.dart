import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despeses/core/providers/app_providers.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/main.dart';
import 'package:despeses/presentation/widgets/expense_row.dart';

/// Guards the dashboard performance fixes: lazy month list (BL-057), the
/// scale-based collapsing hero (BL-058) and the paused stream while the tab is
/// hidden (BL-068).
void main() {
  late AppDatabase db;

  Future<void> insertExpense(String id, DateTime date, {String? description}) =>
      db.into(db.expenses).insert(ExpensesCompanion.insert(
            id: id,
            amount: 1234,
            currency: 'EUR',
            type: 'expense',
            date: date,
            description: Value(description ?? 'row $id'),
          ));

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const DespesesApp(),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // 300 rows in the current month, all already in the past.
    final now = DateTime.now();
    for (var i = 0; i < 300; i++) {
      await insertExpense('e$i', DateTime(now.year, now.month, 1, 0, 0, i));
    }
  });

  tearDown(() async => db.close());

  testWidgets('the month list builds only the visible rows', (tester) async {
    await pumpApp(tester);

    final built = find.byType(ExpenseRow, skipOffstage: false).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(60), reason: 'all 300 rows were built: the list is not lazy');

    await unmount(tester);
  });

  testWidgets('the hero collapses by scrolling without errors and hides the tiles', (tester) async {
    await pumpApp(tester);
    final scroll = find.byType(CustomScrollView).first;

    await tester.drag(scroll, const Offset(0, -80));
    await tester.pump();
    await tester.drag(scroll, const Offset(0, -400));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Fully collapsed: the tiles' fade is complete (nothing painted).
    final fades = tester.widgetList<Opacity>(find.byType(Opacity)).where((o) => o.opacity == 0);
    expect(fades, isNotEmpty);

    await unmount(tester);
  });

  testWidgets('a hidden dashboard ignores writes and catches up when shown again', (tester) async {
    await pumpApp(tester);

    try {
      await tester.tap(find.text('Budgets').last);
      // pumpAndSettle ensures: go_router navigation complete → AppShell rebuilds
      // with navigationShell.currentIndex updated → addPostFrameCallback fires →
      // currentTabIndexProvider updates → DashboardScreen rebuilds with
      // visible=false → StreamBuilder.stream=null. A bare pump(500ms) is not
      // enough because the addPostFrameCallback/Riverpod rebuild chain needs all
      // pending frames to drain.
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      await tester.runAsync(() => insertExpense('new', DateTime.now(), description: 'NEW-ROW'));
      // Let Drift's change notification propagate; use runAsync so real async
      // completes (isolate messages from NativeDatabase) before we check.
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('NEW-ROW', skipOffstage: false), findsNothing,
          reason: 'the hidden dashboard should not rebuild on writes');

      await tester.tap(find.text('Dashboard').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      // Stream re-subscribed; wait for Drift to emit with real async.
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('NEW-ROW'), findsOneWidget);
    } finally {
      // Always unmount — ensures fake-async drains cleanly even on failure,
      // preventing the 10-minute test timeout on unexpected assertion errors.
      await unmount(tester);
    }
  });
}

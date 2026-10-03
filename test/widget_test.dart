import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despeses/main.dart';
import 'package:despeses/presentation/screens/app_shell.dart';

void main() {
  testWidgets('App starts and shows the bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DespesesApp()));
    // Not pumpAndSettle: the Dashboard shows an indeterminate
    // CircularProgressIndicator while its DB query resolves, which never
    // "settles" on its own — a fixed pump is enough to prove the shell renders.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The nav bar itself is a private widget, so assert on what it renders: the
    // shell's Scaffold has a bottomNavigationBar carrying one label per enabled
    // tab. Labels fall back to English while `translationsProvider` (which
    // reads the locale asset bundle) is still resolving.
    expect(find.byType(AppShell), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(
      find.descendant(of: find.byType(AppShell), matching: find.byType(Scaffold)).first,
    );
    expect(scaffold.bottomNavigationBar, isNotNull);

    for (final label in [
      'Dashboard',
      'Transactions',
      'Budgets',
      'Analytics',
      'Manage',
    ]) {
      expect(find.text(label), findsAtLeastNWidgets(1), reason: 'missing nav tab "$label"');
    }
  });
}

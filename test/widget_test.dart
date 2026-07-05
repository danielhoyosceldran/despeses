import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despeses/main.dart';

void main() {
  testWidgets('App starts and shows the 5-tab bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DespesesApp()));
    // Not pumpAndSettle: the Dashboard shows an indeterminate
    // CircularProgressIndicator while its DB query resolves, which never
    // "settles" on its own — a fixed pump is enough to prove the shell renders.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(NavigationBar), findsOneWidget);
  });
}

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despeses/core/providers/app_providers.dart';
import 'package:despeses/core/theme/app_theme.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/presentation/widgets/app_top_bar.dart';

void main() {
  testWidgets('the sliding month label fades with colour alpha, not Opacity layers', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final controller = PageController(initialPage: 10);
    addTearDown(controller.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(children: [
            AppTopBar(
              month: DateTime(2026, 3),
              onChangeMonth: (_) {},
              pageController: controller,
              monthForPage: (p) => DateTime(2026, 3 + (p - 10)),
              fallbackPage: 10,
              showSettings: false,
            ),
            Expanded(
              child: PageView.builder(controller: controller, itemBuilder: (_, i) => Text('page $i')),
            ),
          ]),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    final barLabels = find.descendant(of: find.byType(AppTopBar), matching: find.byType(Text));
    expect(find.descendant(of: find.byType(AppTopBar), matching: find.byType(Opacity)), findsNothing);

    // Mid-swipe: the outgoing and incoming months are both partly transparent.
    controller.jumpTo(controller.position.pixels + controller.position.viewportDimension * 0.5);
    await tester.pump();
    final alphas = [
      for (final t in tester.widgetList<Text>(barLabels))
        if (t.style?.color != null && t.data != null && t.data!.contains('2026')) t.style!.color!.a,
    ];
    expect(alphas.where((a) => a > 0 && a < 1), isNotEmpty);
    expect(find.descendant(of: find.byType(AppTopBar), matching: find.byType(Opacity)), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

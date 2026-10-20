import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despeses/core/theme/app_theme.dart';
import 'package:despeses/presentation/widgets/thin_progress_bar.dart';

void main() {
  final fill = find.descendant(of: find.byType(ThinProgressBar), matching: find.byType(FractionalTranslation));

  Future<void> pumpBar(WidgetTester tester, double value) => tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: IntrinsicHeight(
                child: ThinProgressBar(value: value, fillColor: Colors.red),
              ),
            ),
          ),
        ),
      ));

  testWidgets('the fill animates from empty to its fraction by moving paint only', (tester) async {
    await pumpBar(tester, 0.4);
    Offset translation() => tester.widget<FractionalTranslation>(fill).translation;

    expect(translation().dx, -1, reason: 'starts empty');
    await tester.pump(const Duration(milliseconds: 100));
    expect(translation().dx, inExclusiveRange(-1, -0.6));

    await tester.pumpAndSettle();
    expect(translation().dx, closeTo(-0.6, 1e-9), reason: '40% filled');
    expect(tester.getSize(find.byType(ThinProgressBar)), const Size(200, 6));
  });

  testWidgets('values outside 0..1 are clamped', (tester) async {
    await pumpBar(tester, 3);
    await tester.pumpAndSettle();
    expect(tester.widget<FractionalTranslation>(fill).translation.dx, 0);
  });
}

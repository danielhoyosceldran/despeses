import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/presentation/widgets/numeric_keypad.dart';

void main() {
  testWidgets('digits accumulate as cents (POS-style), so decimals are automatic', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var cents = 0;
    var nextCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => NumericKeypad(
              amountCents: cents,
              onAmountChanged: (v) => setState(() => cents = v),
              onNext: () => nextCalled = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('keypad_1')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('keypad_2')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('keypad_3')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('keypad_4')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(cents, 1234); // shown as 12.34

    await tester.tap(find.byKey(const ValueKey('keypad_⌫')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(cents, 123);

    await tester.tap(find.text('Next'));
    expect(nextCalled, isTrue);
  });
}

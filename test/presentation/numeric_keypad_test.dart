import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/presentation/widgets/numeric_keypad.dart';

void main() {
  testWidgets('digits before comma build euros, digits after comma build cents', (tester) async {
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
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('keypad_2')));
    await tester.pump();
    expect(cents, 1200); // "12" euros, no comma yet

    await tester.tap(find.byKey(const ValueKey('keypad_,')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('keypad_5')));
    await tester.pump();
    expect(cents, 1250); // 12.50

    await tester.tap(find.byKey(const ValueKey('keypad_⌫')));
    await tester.pump();
    expect(cents, 1200); // back to 12.00, still in cents mode

    await tester.tap(find.byKey(const ValueKey('keypad_⌫')));
    await tester.pump();
    expect(cents, 1200); // comma mode cleared, whole part untouched

    await tester.tap(find.byKey(const ValueKey('keypad_⌫')));
    await tester.pump();
    expect(cents, 100); // "1" euro

    await tester.tap(find.byKey(const ValueKey('keypad_next')));
    expect(nextCalled, isTrue);
  });

  testWidgets('00 inserts two zeros respecting the active segment', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var cents = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => NumericKeypad(
              amountCents: cents,
              onAmountChanged: (v) => setState(() => cents = v),
              onNext: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('keypad_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('keypad_00')));
    await tester.pump();
    expect(cents, 10000); // 100 euros
  });
}

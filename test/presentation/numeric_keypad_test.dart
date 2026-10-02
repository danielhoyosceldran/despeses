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

  testWidgets('seeded amount keeps its cents when editing continues', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Edit mode: the caller seeds an existing amount of 12,50. The keypad used
    // to seed only the whole part, so the first key press re-emitted from 12,00
    // and silently dropped the ,50.
    var cents = 1250;

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

    // Backspace clears the last cents digit, so 12,50 → 12,5 — the same amount,
    // not 1,00 as before.
    await tester.tap(find.byKey(const ValueKey('keypad_⌫')));
    await tester.pump();
    expect(cents, 1250);

    // Second backspace drops the cents entirely, leaving the euros untouched.
    await tester.tap(find.byKey(const ValueKey('keypad_⌫')));
    await tester.pump();
    expect(cents, 1200);
  });

  testWidgets('seeded whole-euro amount starts outside cents mode', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var cents = 1200;

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

    // No cents to seed, so a digit still appends to the euros.
    await tester.tap(find.byKey(const ValueKey('keypad_3')));
    await tester.pump();
    expect(cents, 12300);
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

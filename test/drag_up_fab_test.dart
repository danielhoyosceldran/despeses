import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despeses/core/haptics/haptics.dart';
import 'package:despeses/presentation/widgets/drag_up_fab.dart';

class _NoHaptics implements HapticsService {
  @override
  Future<void> light() async {}
  @override
  Future<void> medium() async {}
  @override
  Future<void> heavy() async {}
  @override
  Future<void> selection() async {}
  @override
  Future<void> vibrate() async {}
}

Widget _app({ValueChanged<Object?>? onResult}) => ProviderScope(
      overrides: [hapticsProvider.overrideWithValue(_NoHaptics())],
      child: MaterialApp(
        home: Scaffold(
          floatingActionButton: DragUpFab(
            onResult: onResult,
            pageBuilder: (context, close) => Scaffold(
              key: const Key('page'),
              body: Center(
                child: ElevatedButton(
                  onPressed: () => close(true),
                  child: const Text('SAVE'),
                ),
              ),
            ),
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );

void main() {
  testWidgets('drag keeps gesture alive: FAB follows and sheet rises then opens',
      (tester) async {
    Object? result;
    await tester.pumpWidget(_app(onResult: (r) => result = r));

    final start = tester.getCenter(find.byType(FloatingActionButton));
    final iconY0 = tester.getCenter(find.byType(Icon)).dy;

    final g = await tester.startGesture(start);
    // Slow drag well past the 72px threshold, WITHOUT releasing.
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Gesture stayed alive → FAB icon followed the finger up.
    final iconY1 = tester.getCenter(find.byType(Icon)).dy;
    expect(iconY1, lessThan(iconY0 - 100), reason: 'FAB should follow finger');

    // Sheet is present and slid up from the bottom (past threshold).
    final page = find.byKey(const Key('page'));
    expect(page, findsOneWidget, reason: 'sheet should be shown while dragging');
    final screenH = tester.getSize(find.byType(MaterialApp)).height;
    expect(tester.getTopLeft(page).dy, lessThan(screenH - 100),
        reason: 'sheet should track finger, not sit at the bottom');

    // Release past threshold → completes open.
    await g.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(page).dy, moveToZero(), reason: 'fully open');

    // Close via the page callback → removed + result reported.
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page')), findsNothing);
    expect(result, isTrue);
  });

  testWidgets('release below threshold cancels (no result)', (tester) async {
    Object? result = 'unset';
    await tester.pumpWidget(_app(onResult: (r) => result = r));

    final start = tester.getCenter(find.byType(FloatingActionButton));
    final g = await tester.startGesture(start);
    // Tiny drag, below 72px threshold.
    await g.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 16));
    await g.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page')), findsNothing, reason: 'cancelled');
    expect(result, isNot(true), reason: 'cancel must not signal a save');
  });
}

Matcher moveToZero() => lessThan(1.0);

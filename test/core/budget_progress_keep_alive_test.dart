import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/core/providers/app_providers.dart';
import 'package:despeses/data/database.dart';

void main() {
  testWidgets('an unwatched budget progress stream is released after its short keep-alive',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);

    final month = DateTime(2026, 3);
    final sub = container.listen(budgetProgressProvider(month), (_, _) {});
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    sub.close();

    // Still cached right after the last listener left (quick tab switches).
    await tester.pump(budgetProgressKeepAlive - const Duration(seconds: 1));
    expect(container.exists(budgetProgressProvider(month)), isTrue);

    // Gone shortly after, instead of staying subscribed for ten minutes.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(container.exists(budgetProgressProvider(month)), isFalse);
  });
}

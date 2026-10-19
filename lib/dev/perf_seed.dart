import 'dart:developer' as developer;
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../domain/repositories/budget_repository.dart';
import '../domain/repositories/category_repository.dart';
import '../domain/repositories/recurring_repository.dart';

/// DEV-ONLY performance dataset (BL-056). Enabled with
/// `--dart-define=SEED_PERF_DATA=true` in debug/profile builds; the constant is
/// false in release, so this code is tree-shaken out of shipped builds.
/// See docs/performance.md for the profiling procedure that uses it.
const bool kSeedPerfData = bool.fromEnvironment('SEED_PERF_DATA') && !kReleaseMode;

const _uuid = Uuid();

/// Fills an *empty* database (no transactions yet) with ~5 years of realistic
/// data: ~10k transactions of every type, tags on ~30% of them, a few
/// budgets (category, tag and range) and recurring templates. Does nothing if
/// any transaction exists, so it never touches real data and re-launching
/// with the flag is a no-op. Deterministic (fixed seed) so measurements are
/// comparable across runs.
Future<void> seedPerfDatasetIfEmpty(AppDatabase db, CategoryRepository categoryRepo, {int years = 5}) async {
  final existing = await (db.selectOnly(db.expenses)..addColumns([db.expenses.id.count()]))
      .map((r) => r.read(db.expenses.id.count()))
      .getSingle();
  if ((existing ?? 0) > 0) return;

  final watch = Stopwatch()..start();
  final rng = Random(42);
  final categories = await db.select(db.categories).get();
  final parentIds = {for (final c in categories) c.parentId};
  List<Category> leaves(String type) =>
      categories.where((c) => c.type == type && !parentIds.contains(c.id)).toList();
  final expenseLeaves = leaves('expense');
  final incomeLeaves = leaves('income');
  final refundLeaves = leaves('refund');
  final savingsLeaves = leaves('ahorro');
  final tags = await db.select(db.tags).get();
  final payments = await db.select(db.paymentMethods).get();
  const currency = 'EUR';
  const descriptions = ['Mercadona', 'Bar', 'Gasolina', 'Amazon', 'Farmacia', 'Cine', 'Taxi', 'Ropa', 'Super', 'Cena'];

  final now = DateTime.now();
  final start = DateTime(now.year - years, now.month, now.day);
  var count = 0;

  await db.batch((batch) {
    void add(String type, Category category, int cents, DateTime date) {
      final id = _uuid.v4();
      batch.insert(
        db.expenses,
        ExpensesCompanion.insert(
          id: id,
          amount: cents,
          currency: currency,
          type: type,
          date: date,
          description: Value(type == 'expense' ? descriptions[rng.nextInt(descriptions.length)] : null),
          categoryId: Value(category.id),
          paymentMethodId: Value(payments.isEmpty ? null : payments[rng.nextInt(payments.length)].id),
          createdAt: Value(date),
        ),
      );
      if (tags.isNotEmpty && rng.nextDouble() < 0.3) {
        final first = rng.nextInt(tags.length);
        final tagIds = {tags[first].id, if (rng.nextBool()) tags[(first + 1) % tags.length].id};
        for (final tagId in tagIds) {
          batch.insert(db.expenseTags, ExpenseTagsCompanion.insert(expenseId: id, tagId: tagId));
        }
      }
      count++;
    }

    for (var day = start; !day.isAfter(now); day = DateTime(day.year, day.month, day.day + 1)) {
      // ~5 expenses a day, at varied times (several sharing a timestamp).
      final perDay = 2 + rng.nextInt(7);
      for (var i = 0; i < perDay; i++) {
        final at = DateTime(day.year, day.month, day.day, 8 + rng.nextInt(14), rng.nextInt(4) * 15);
        final cents = rng.nextDouble() < 0.85 ? 150 + rng.nextInt(4000) : 5000 + rng.nextInt(30000);
        add('expense', expenseLeaves[rng.nextInt(expenseLeaves.length)], cents, at);
      }
      if (day.day == 1) {
        add('income', incomeLeaves.first, 220000 + rng.nextInt(20000), day);
        add('ahorro', savingsLeaves[rng.nextInt(savingsLeaves.length)], 30000, day);
      }
      if (rng.nextDouble() < 0.05) {
        add('refund', refundLeaves[rng.nextInt(refundLeaves.length)], 500 + rng.nextInt(5000), day);
      }
    }
  });

  final budgets = BudgetRepository(db, categoryRepo);
  for (var i = 0; i < 3 && i < expenseLeaves.length; i++) {
    await budgets.create(
      name: 'Perf budget ${i + 1}',
      categoryId: expenseLeaves[i].id,
      amountCents: 20000 * (i + 1),
      currency: currency,
      budgetType: 'monthly',
    );
  }
  if (tags.isNotEmpty) {
    await budgets.create(
      name: 'Perf tag budget',
      tagId: tags.first.id,
      amountCents: 30000,
      currency: currency,
      budgetType: 'monthly',
    );
  }
  final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  await budgets.create(
    name: 'Perf range budget',
    categoryId: expenseLeaves.last.id,
    amountCents: 100000,
    currency: currency,
    budgetType: 'range',
    startsMonth: month,
    endsMonth: month,
  );

  // Templates start next month so they don't flood the pending inbox with
  // years of past occurrences.
  final recurring = RecurringRepository(db);
  final nextMonth = DateTime(now.year, now.month + 1, 1);
  for (final (cents, frequency) in [(85000, 'monthly'), (4500, 'monthly'), (1200, 'weekly'), (9900, 'yearly')]) {
    await recurring.create(
      amountCents: cents,
      currency: currency,
      type: 'expense',
      frequency: frequency,
      startDate: nextMonth,
      description: 'Perf recurring $frequency',
      categoryId: expenseLeaves[rng.nextInt(expenseLeaves.length)].id,
    );
  }

  developer.log('seeded $count transactions in ${watch.elapsedMilliseconds} ms', name: 'PerfSeed');
}

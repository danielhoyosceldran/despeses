import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/expense_repository.dart';

/// Refund ↔ expense links (BL-071): optional, many-to-many, same month only.
void main() {
  late AppDatabase db;
  late ExpenseRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExpenseRepository(db);
  });

  tearDown(() async => db.close());

  Future<String> add(String type, DateTime date, {int amount = 1000, List<String> links = const []}) =>
      repo.create(
        amountCents: amount,
        currency: 'EUR',
        type: type,
        date: date,
        description: type,
        linkedExpenseIds: links,
      );

  Matcher violation(RefundLinkViolation v) =>
      throwsA(isA<RefundLinkException>().having((e) => e.violation, 'violation', v));

  test('a refund links to several expenses and an expense to several refunds', () async {
    final e1 = await add('expense', DateTime(2026, 10, 1));
    final e2 = await add('expense', DateTime(2026, 10, 31, 23, 59));
    final r1 = await add('refund', DateTime(2026, 10, 15), links: [e1, e2, e1]);
    final r2 = await add('refund', DateTime(2026, 10, 20), links: [e1]);

    expect((await repo.linkedExpenseIdsOf(r1)).toSet(), {e1, e2});
    expect((await repo.linkedExpensesOf(r1)).map((e) => e.id), [e2, e1]);
    expect((await repo.refundsLinkedTo(e1)).map((e) => e.id), [r2, r1]);
    expect(await repo.refundsLinkedTo(e2), hasLength(1));
  });

  test('a refund without links is valid', () async {
    final r = await add('refund', DateTime(2026, 10, 15));
    expect(await repo.linkedExpenseIdsOf(r), isEmpty);
  });

  test('linking an expense of another month is refused and saves nothing', () async {
    final september = await add('expense', DateTime(2026, 9, 30, 23, 59));
    await expectLater(
        add('refund', DateTime(2026, 10, 1), links: [september]), violation(RefundLinkViolation.monthMismatch));
    expect(await db.select(db.expenses).get(), hasLength(1));
    expect(await db.select(db.expenseRefundLinks).get(), isEmpty);
  });

  test('only expenses can be linked', () async {
    final income = await add('income', DateTime(2026, 10, 1));
    await expectLater(
        add('refund', DateTime(2026, 10, 2), links: [income]), violation(RefundLinkViolation.notAnExpense));
    await expectLater(
        add('refund', DateTime(2026, 10, 2), links: ['missing']), violation(RefundLinkViolation.notAnExpense));
  });

  test('links are ignored on a non-refund create', () async {
    final e = await add('expense', DateTime(2026, 10, 1));
    await add('income', DateTime(2026, 10, 2), links: [e]);
    expect(await db.select(db.expenseRefundLinks).get(), isEmpty);
  });

  test('update replaces links; null keeps them', () async {
    final e1 = await add('expense', DateTime(2026, 10, 1));
    final e2 = await add('expense', DateTime(2026, 10, 2));
    final r = await add('refund', DateTime(2026, 10, 3), links: [e1]);

    await repo.update(r, amountCents: 500);
    expect(await repo.linkedExpenseIdsOf(r), [e1]);

    await repo.update(r, linkedExpenseIds: [e2]);
    expect(await repo.linkedExpenseIdsOf(r), [e2]);

    await repo.update(r, linkedExpenseIds: []);
    expect(await repo.linkedExpenseIdsOf(r), isEmpty);
  });

  test('moving a linked refund to another month is refused', () async {
    final e = await add('expense', DateTime(2026, 10, 1));
    final r = await add('refund', DateTime(2026, 10, 3), links: [e]);

    await expectLater(repo.update(r, date: DateTime(2026, 11, 1)), violation(RefundLinkViolation.monthMismatch));
    expect((await repo.byId(r))!.date, DateTime(2026, 10, 3));

    // Unlinking in the same save allows the move.
    await repo.update(r, date: DateTime(2026, 11, 1), linkedExpenseIds: []);
    expect((await repo.byId(r))!.date, DateTime(2026, 11, 1));
  });

  test('a refund that changes type loses its links', () async {
    final e = await add('expense', DateTime(2026, 10, 1));
    final r = await add('refund', DateTime(2026, 10, 3), links: [e]);
    await repo.update(r, type: 'income');
    expect(await db.select(db.expenseRefundLinks).get(), isEmpty);
  });

  test('an expense with refunds cannot change type or month', () async {
    final e = await add('expense', DateTime(2026, 10, 1));
    await add('refund', DateTime(2026, 10, 3), links: [e]);

    await expectLater(repo.update(e, type: 'ahorro'), violation(RefundLinkViolation.expenseHasRefunds));
    await expectLater(repo.update(e, date: DateTime(2026, 9, 30)), violation(RefundLinkViolation.monthMismatch));
    final stored = (await repo.byId(e))!;
    expect(stored.type, 'expense');
    expect(stored.date, DateTime(2026, 10, 1));

    // Same month is fine.
    await repo.update(e, date: DateTime(2026, 10, 28));
    expect((await repo.byId(e))!.date, DateTime(2026, 10, 28));
  });

  test('deleting an expense leaves its refunds unlinked', () async {
    final e1 = await add('expense', DateTime(2026, 10, 1));
    final e2 = await add('expense', DateTime(2026, 10, 2));
    final r1 = await add('refund', DateTime(2026, 10, 3), links: [e1, e2]);
    final r2 = await add('refund', DateTime(2026, 10, 4), links: [e1]);

    expect(await repo.refundsUnlinkedByDeleting([e1]), 2);
    expect(await repo.refundsUnlinkedByDeleting([e1, r2]), 1);

    await repo.delete(e1);
    expect(await repo.linkedExpenseIdsOf(r1), [e2]);
    expect(await repo.linkedExpenseIdsOf(r2), isEmpty);
    expect(await repo.byId(r2), isNotNull);
  });

  test('refundLinkCandidates lists the month\'s expenses only', () async {
    final inMonth = await add('expense', DateTime(2026, 10, 31, 23, 59));
    await add('expense', DateTime(2026, 11, 1));
    await add('expense', DateTime(2026, 9, 30, 23, 59));
    await add('income', DateTime(2026, 10, 5));

    final candidates = await repo.refundLinkCandidates(DateTime(2026, 10, 15));
    expect(candidates.map((e) => e.id), [inMonth]);
  });

  test('linkedExpensesByRefund resolves many refunds at once', () async {
    final e1 = await add('expense', DateTime(2026, 10, 1));
    final e2 = await add('expense', DateTime(2026, 10, 2));
    final r1 = await add('refund', DateTime(2026, 10, 3), links: [e2, e1]);
    final r2 = await add('refund', DateTime(2026, 10, 4));

    final byRefund = await repo.linkedExpensesByRefund([r1, r2]);
    expect(byRefund.keys, [r1]);
    expect(byRefund[r1]!.map((e) => e.id), [e1, e2]);
  });
}

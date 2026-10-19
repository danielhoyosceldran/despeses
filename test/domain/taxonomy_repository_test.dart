import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/category_repository.dart';
import 'package:despeses/domain/repositories/expense_repository.dart';
import 'package:despeses/domain/repositories/recurring_repository.dart';
import 'package:despeses/domain/repositories/tag_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('reordering categories persists new position order', () async {
    final repo = CategoryRepository(db);
    final roots = await repo.listAll();
    final ids = roots.map((c) => c.id).toList();
    final reversed = ids.reversed.toList();

    await repo.reorder(null, reversed);

    final after = await repo.listAll();
    expect(after.map((c) => c.id).toList(), reversed);
  });

  test('deleting a tag group reassigns its tags to "ungrouped" instead of failing', () async {
    final groupRepo = TagGroupRepository(db);
    final tagRepo = TagRepository(db);
    final ungrouped = await groupRepo.ungrouped();

    final groupId = await groupRepo.create('custom group');
    final tagId = await tagRepo.create(name: 'custom tag', tagGroupId: groupId);

    await groupRepo.delete(groupId);

    final tag = (await tagRepo.listAll()).firstWhere((t) => t.id == tagId);
    expect(tag.tagGroupId, ungrouped.id);

    final groups = await groupRepo.listAll();
    expect(groups.any((g) => g.id == groupId), isFalse);
  });

  test('renaming a default category/tag detaches it from the i18n key', () async {
    final repo = CategoryRepository(db);
    final root = (await repo.listAll()).first;
    expect(root.isDefault, isTrue);

    await repo.rename(root.id, 'My custom name');

    final updated = (await repo.listAll()).firstWhere((c) => c.id == root.id);
    expect(updated.isDefault, isFalse);
    expect(updated.name, 'My custom name');
  });

  group('createSubcategory keeps the leaf-only rule', () {
    Future<String> leafWithUsages(CategoryRepository repo) async {
      final leafId = await repo.create(name: 'Leaf', type: 'expense');
      await ExpenseRepository(db).create(
          amountCents: 100, currency: 'EUR', type: 'expense', date: DateTime(2026, 3, 1), categoryId: leafId);
      await RecurringRepository(db).create(
        amountCents: 100,
        currency: 'EUR',
        type: 'expense',
        frequency: 'monthly',
        startDate: DateTime(2026, 1, 1),
        categoryId: leafId,
      );
      await RecurringRepository(db).materializeDue(now: DateTime(2026, 1, 15));
      return leafId;
    }

    test('moves transactions, templates and pending occurrences to a new "Others" child', () async {
      final repo = CategoryRepository(db);
      final leafId = await leafWithUsages(repo);

      final created = await repo.createSubcategory(name: 'Child', parentId: leafId, othersName: 'Others');

      final children = await repo.listChildren(leafId);
      expect(children.map((c) => c.name).toSet(), {'Child', 'Others'});
      final othersId = children.firstWhere((c) => c.name == 'Others').id;
      expect(created.movedToId, othersId);
      expect(created.movedCount, 3);
      expect((await db.select(db.expenses).get()).single.categoryId, othersId);
      expect((await db.select(db.recurrings).get()).single.categoryId, othersId);
      expect((await db.select(db.recurringOccurrences).get()).single.categoryId, othersId);
    });

    test('uses the new child when it is itself named "Others"', () async {
      final repo = CategoryRepository(db);
      final leafId = await leafWithUsages(repo);

      final created = await repo.createSubcategory(name: 'Others', parentId: leafId, othersName: 'Others');

      expect((await repo.listChildren(leafId)).length, 1);
      expect(created.movedToId, created.id);
      expect((await db.select(db.expenses).get()).single.categoryId, created.id);
    });

    test('creates no "Others" when the parent has no usages or children already', () async {
      final repo = CategoryRepository(db);
      final emptyLeaf = await repo.create(name: 'Empty', type: 'expense');
      final first = await repo.createSubcategory(name: 'A', parentId: emptyLeaf, othersName: 'Others');
      final second = await repo.createSubcategory(name: 'B', parentId: emptyLeaf, othersName: 'Others');

      expect(first.movedCount, 0);
      expect(second.movedCount, 0);
      expect((await repo.listChildren(emptyLeaf)).map((c) => c.name).toSet(), {'A', 'B'});
    });
  });
}

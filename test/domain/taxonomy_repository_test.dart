import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/repositories/category_repository.dart';
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
}

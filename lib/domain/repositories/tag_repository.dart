import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';

const _uuid = Uuid();
const ungroupedKey = 'tag_group.ungrouped';

class TagGroupRepository {
  TagGroupRepository(this._db);

  final AppDatabase _db;

  Future<List<TagGroup>> listAll() {
    return (_db.select(_db.tagGroups)
          ..orderBy([(g) => OrderingTerm(expression: g.position)]))
        .get();
  }

  Future<TagGroup> ungrouped() async {
    return (_db.select(_db.tagGroups)..where((g) => g.name.equals(ungroupedKey)))
        .getSingle();
  }

  Future<String> create(String name) async {
    final id = _uuid.v4();
    final all = await listAll();
    await _db.into(_db.tagGroups).insert(
          TagGroupsCompanion.insert(id: id, name: name, position: Value(all.length)),
        );
    return id;
  }

  Future<void> rename(String id, String newName) async {
    await (_db.update(_db.tagGroups)..where((g) => g.id.equals(id))).write(
      TagGroupsCompanion(name: Value(newName), updatedAt: Value(DateTime.now())),
    );
  }

  /// Deleting a group first reassigns its tags to "ungrouped", then deletes it
  /// (the group->tag FK is RESTRICT, so it would otherwise fail).
  Future<void> delete(String id) async {
    final target = await ungrouped();
    if (target.id == id) {
      throw StateError('The default "ungrouped" tag group cannot be deleted.');
    }
    await (_db.update(_db.tags)..where((t) => t.tagGroupId.equals(id))).write(
      TagsCompanion(tagGroupId: Value(target.id)),
    );
    await (_db.delete(_db.tagGroups)..where((g) => g.id.equals(id))).go();
  }

  Future<void> reorder(List<String> orderedIds) async {
    await _db.batch((batch) {
      for (var i = 0; i < orderedIds.length; i++) {
        batch.update(
          _db.tagGroups,
          TagGroupsCompanion(position: Value(i)),
          where: (g) => g.id.equals(orderedIds[i]),
        );
      }
    });
  }
}

class TagRepository {
  TagRepository(this._db);

  final AppDatabase _db;

  Future<List<Tag>> listAll() {
    return (_db.select(_db.tags)
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .get();
  }

  Future<List<Tag>> listByGroup(String tagGroupId) {
    return (_db.select(_db.tags)
          ..where((t) => t.tagGroupId.equals(tagGroupId))
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .get();
  }

  Future<String> create({
    required String name,
    required String tagGroupId,
    String? color,
    String? icon,
  }) async {
    final id = _uuid.v4();
    final siblings = await listByGroup(tagGroupId);
    await _db.into(_db.tags).insert(
          TagsCompanion.insert(
            id: id,
            tagGroupId: tagGroupId,
            name: name,
            color: Value(color),
            icon: Value(icon),
            position: Value(siblings.length),
          ),
        );
    return id;
  }

  Future<void> rename(String id, String newName) async {
    await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
      TagsCompanion(
        name: Value(newName),
        isDefault: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateAppearance(String id, {String? color, String? icon}) async {
    await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
      TagsCompanion(color: Value(color), icon: Value(icon), updatedAt: Value(DateTime.now())),
    );
  }

  Future<int> budgetCount(String id) async {
    final count = _db.budgets.id.count();
    final query = _db.selectOnly(_db.budgets)
      ..addColumns([count])
      ..where(_db.budgets.tagId.equals(id));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
  }

  Future<void> reorder(String tagGroupId, List<String> orderedIds) async {
    await _db.batch((batch) {
      for (var i = 0; i < orderedIds.length; i++) {
        batch.update(
          _db.tags,
          TagsCompanion(position: Value(i)),
          where: (t) => t.id.equals(orderedIds[i]),
        );
      }
    });
  }
}

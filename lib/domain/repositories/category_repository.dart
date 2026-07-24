import 'dart:math';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import 'errors.dart';

const _uuid = Uuid();

class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;

  Future<List<Category>> listAll() {
    return (_db.select(_db.categories)
          ..orderBy([
            (c) => OrderingTerm(expression: c.position),
            (c) => OrderingTerm(expression: c.id),
          ]))
        .get();
  }

  /// Children of [parentId] (null = roots). When listing roots, [type] filters
  /// the tree to a single transaction-type forest (expense/income/refund/ahorro).
  Future<List<Category>> listChildren(String? parentId, {String? type}) {
    final query = _db.select(_db.categories)
      ..orderBy([
        (c) => OrderingTerm(expression: c.position),
        (c) => OrderingTerm(expression: c.id),
      ]);
    if (parentId == null) {
      query.where((c) => c.parentId.isNull());
      if (type != null) query.where((c) => c.type.equals(type));
    } else {
      query.where((c) => c.parentId.equals(parentId));
    }
    return query.get();
  }

  Future<Category?> byId(String id) {
    return (_db.select(_db.categories)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  /// A category is a leaf when it has no children. Only leaves may be assigned
  /// to a transaction (rule: leaf-only categorization).
  Future<bool> isLeaf(String id) async {
    final children = await listChildren(id);
    return children.isEmpty;
  }

  /// Creates a category. Roots default to [type] `'expense'`; children inherit
  /// their parent's type so a whole tree stays within one transaction type.
  Future<String> create({
    required String name,
    String? parentId,
    String? type,
    String? color,
    String? icon,
  }) async {
    final id = _uuid.v4();
    var resolvedType = type ?? 'expense';
    if (parentId != null) {
      final parent = await byId(parentId);
      if (parent != null) resolvedType = parent.type;
    }
    final siblings = await listChildren(parentId);
    final position = siblings.isEmpty
        ? 0
        : siblings.map((s) => s.position).reduce(max) + 1;
    await guardUniqueName(name, () => _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            id: id,
            name: name,
            type: Value(resolvedType),
            parentId: Value(parentId),
            color: Value(color),
            icon: Value(icon),
            position: Value(position),
          ),
        ));
    return id;
  }

  /// Renaming a default category detaches it from the i18n key (`is_default = false`).
  Future<void> rename(String id, String newName) async {
    await guardUniqueName(newName, () => (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(newName),
        isDefault: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    ));
  }

  Future<void> updateAppearance(String id, {String? color, String? icon}) async {
    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        color: Value(color),
        icon: Value(icon),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Number of budgets that would be cascade-deleted with this category (for the
  /// warning dialog before deletion) — mirrors `getBudgetCount` in the web app.
  Future<int> budgetCount(String id) async {
    final descendants = await descendantIds(id);
    final ids = {id, ...descendants};
    final count = _db.budgets.id.count();
    final query = _db.selectOnly(_db.budgets)
      ..addColumns([count])
      ..where(_db.budgets.categoryId.isIn(ids));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
  }

  /// All descendant ids (children, grandchildren, ...), excluding [id] itself.
  Future<Set<String>> descendantIds(String id) async {
    return (await descendantMap())[id] ?? const <String>{};
  }

  /// Every category id → the set of all its descendant ids, computed from a
  /// single full scan. Hot analytics loops (breakdown/ranking/monthlyByRoot)
  /// need the subtree of many categories at once; calling [descendantIds] per
  /// node re-scanned the whole table each time (R2 N+1). Build the map once and
  /// look each subtree up in O(1).
  Future<Map<String, Set<String>>> descendantMap() async {
    final all = await listAll();
    final byParent = <String?, List<Category>>{};
    for (final c in all) {
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    final memo = <String, Set<String>>{};
    Set<String> collect(String id) {
      final cached = memo[id];
      if (cached != null) return cached;
      final result = <String>{};
      for (final child in byParent[id] ?? const <Category>[]) {
        result.add(child.id);
        result.addAll(collect(child.id));
      }
      return memo[id] = result;
    }

    for (final c in all) {
      collect(c.id);
    }
    return memo;
  }

  Future<void> reorder(String? parentId, List<String> orderedIds) async {
    await _db.batch((batch) {
      for (var i = 0; i < orderedIds.length; i++) {
        batch.update(
          _db.categories,
          CategoriesCompanion(position: Value(i)),
          where: (c) => c.id.equals(orderedIds[i]),
        );
      }
    });
  }
}

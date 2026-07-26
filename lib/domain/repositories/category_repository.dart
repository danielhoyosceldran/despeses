import 'dart:math';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import 'errors.dart';

const _uuid = Uuid();

class CategoryRepository {
  CategoryRepository(this._db) {
    // Any write to `categories` drops the memoized descendant map. Listening to
    // Drift's table-update stream (rather than clearing it in each mutator)
    // also covers writes that bypass this repo: seeding, import, restore.
    // The subscription lives as long as the repository, which lives as long as
    // the database instance, so it is never cancelled by design.
    _db.tableUpdates(TableUpdateQuery.onTable(_db.categories)).listen((_) {
      _descendantMapCache = null;
    });
  }

  final AppDatabase _db;

  /// Memoized [descendantMap]. Invalidated by the `categories` table-update
  /// subscription set up in the constructor.
  Map<String, Set<String>>? _descendantMapCache;

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

  /// The UNIQUE index on `{type, parentId, name}` does not constrain roots:
  /// their `parent_id` is NULL, and SQLite treats every NULL as distinct, so two
  /// roots of the same type could share a name. Enforce it here instead (a
  /// partial index over `COALESCE(parent_id,'')` would need a migration).
  Future<void> _assertRootNameFree(String name, String type, {String? excludingId}) async {
    final roots = await listChildren(null, type: type);
    final clash = roots.any((c) => c.id != excludingId && c.name == name);
    if (clash) throw DuplicateNameException(name);
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
    } else {
      await _assertRootNameFree(name, resolvedType);
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
    final target = await byId(id);
    if (target != null && target.parentId == null) {
      await _assertRootNameFree(newName, target.type, excludingId: id);
    }
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

  /// Deletes [id] and recompacts the remaining siblings' positions to a
  /// contiguous 0..n-1 range, so a later `create` (which appends at
  /// `max(position)+1`) can never collide with a gap left by this delete.
  Future<void> delete(String id) async {
    final target = await byId(id);
    await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
    if (target == null) return;
    final siblings = await listChildren(target.parentId, type: target.parentId == null ? target.type : null);
    await _db.batch((batch) {
      for (var i = 0; i < siblings.length; i++) {
        batch.update(
          _db.categories,
          CategoriesCompanion(position: Value(i)),
          where: (c) => c.id.equals(siblings[i].id),
        );
      }
    });
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
  ///
  /// The result is memoized until `categories` changes, so the many callers per
  /// dashboard/analytics load (one per budget, one per goal) share a single full
  /// scan instead of re-scanning the table each time (R32).
  Future<Map<String, Set<String>>> descendantMap() async {
    final cached = _descendantMapCache;
    if (cached != null) return cached;
    final all = await listAll();
    final byParent = <String?, List<Category>>{};
    for (final c in all) {
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    final memo = <String, Set<String>>{};
    // Nodes on the current recursion path. A parentId cycle (only reachable via
    // a corrupt import/restore) would otherwise recurse forever.
    final inProgress = <String>{};
    Set<String> collect(String id) {
      final cached = memo[id];
      if (cached != null) return cached;
      if (!inProgress.add(id)) return const <String>{};
      final result = <String>{};
      for (final child in byParent[id] ?? const <Category>[]) {
        result.add(child.id);
        result.addAll(collect(child.id));
      }
      inProgress.remove(id);
      return memo[id] = result;
    }

    for (final c in all) {
      collect(c.id);
    }
    return _descendantMapCache = memo;
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

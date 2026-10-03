import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/backup/backup_service.dart';
import 'tables.dart';

part 'database.g.dart';

const _uuid = Uuid();

/// DEV-ONLY escape hatch. When true, a schema upgrade WIPES all data and
/// reseeds from scratch (the app's old behavior). It MUST stay false in any
/// build used with real data — flip it only in a throwaway dev checkout when
/// reworking the seed. Real upgrades use the data-preserving steps in
/// [AppDatabase.migration]'s onUpgrade instead.
const bool _devReseedOnUpgrade = false;

/// A default category node in the seed forest. [key] is an i18n key (see
/// displayNameFor); [children] are its subcategories, recursively.
class _Cat {
  const _Cat(this.key, [this.children = const []]);
  final String key;
  final List<_Cat> children;
}

/// Inserts [node] and its subtree, assigning [position] among its siblings and
/// linking children to their parent via parentId.
/// Queues [node] (and its subtree) for insertion in [batch]. Ids are
/// generated client-side, so children can reference their parent without
/// waiting for an insert to complete.
void _insertCategoryNode(
  AppDatabase db,
  Batch batch, {
  required String type,
  String? parentId,
  required _Cat node,
  required int position,
}) {
  final id = _uuid.v4();
  batch.insert(
    db.categories,
    CategoriesCompanion.insert(
      id: id,
      name: node.key,
      type: Value(type),
      parentId: Value(parentId),
      isDefault: const Value(true),
      position: Value(position),
    ),
  );
  for (var i = 0; i < node.children.length; i++) {
    _insertCategoryNode(db, batch, type: type, parentId: id, node: node.children[i], position: i);
  }
}

@DriftDatabase(tables: [
  Profile,
  TagGroups,
  Tags,
  Categories,
  PaymentMethods,
  Events,
  Projects,
  Expenses,
  ExpenseTags,
  Budgets,
  Recurrings,
  RecurringTags,
  RecurringOccurrences,
  SavingsGoals,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor, BackupService? backupService])
      : _backupService = backupService ?? BackupService(),
        super(executor ?? _openConnection());

  final BackupService _backupService;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'despeses');
  }

  /// Oldest schema version onUpgrade accepts. Every install starts at or
  /// above it; see docs/database_baseline.md before changing it.
  static const int baselineSchemaVersion = 9;

  /// Schema version this build creates/migrates to. Static so code without a
  /// live connection (e.g. backup validation) can check a file against it.
  static const int currentSchemaVersion = 10;

  @override
  int get schemaVersion => currentSchemaVersion;

  /// Columns each schema bump after the baseline added to an EXISTING table:
  /// version → table → SQL column names, in ascending version order. The
  /// single source for onUpgrade's addColumn steps and for backup validation
  /// ([schemaColumnsAt]), which must know which columns a file of a given
  /// version is supposed to have.
  static const Map<int, Map<String, Set<String>>> columnsAddedInVersion = {
    10: {'profile': {'favorite_payment_method_id'}}, // BL-024
  };

  /// Every table's columns (SQL names) at schema [version], between
  /// [baselineSchemaVersion] and [currentSchemaVersion]: the current drift
  /// definitions minus the columns added in later versions. Tables added
  /// after the baseline would need the same treatment here.
  static Map<String, Set<String>> schemaColumnsAt(int version) {
    final columns = {for (final e in _currentColumns.entries) e.key: {...e.value}};
    for (final step in columnsAddedInVersion.entries) {
      if (step.key <= version) continue;
      for (final table in step.value.entries) {
        columns[table.key]!.removeAll(table.value);
      }
    }
    return columns;
  }

  static final Map<String, Set<String>> _currentColumns = _readCurrentColumns();

  /// Reads the table definitions from a throwaway, never-opened instance (no
  /// query runs, so the in-memory executor is never even created).
  static Map<String, Set<String>> _readCurrentColumns() {
    final db = _SchemaProbe();
    final columns = {
      for (final table in db.allTables) table.actualTableName: {for (final c in table.$columns) c.name},
    };
    unawaited(db.close());
    return columns;
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaults(this);
          await _createIndexes(this);
          await _createRecurringIndexes(this);
        },
        onUpgrade: (m, from, to) async {
          // Auto-backup before any schema change — never throws.
          await _backupService.createAutoBackup();

          if (_devReseedOnUpgrade) {
            await _rebuildFromScratch(this, m);
            return;
          }

          // BASELINE: v9 is the oldest schema any install carries (see
          // docs/database_baseline.md). Earlier upgrade steps were removed on
          // purpose, so a pre-baseline file cannot be migrated. Refuse it
          // instead of guessing — the auto-backup above already holds it.
          if (from < baselineSchemaVersion) {
            throw UnsupportedError(
                'Database schema v$from predates the v$baselineSchemaVersion '
                'baseline and cannot be upgraded.');
          }

          // Columns added to existing tables, driven by columnsAddedInVersion
          // (v10, BL-024: profile.favorite_payment_method_id). Other kinds of
          // step (new tables, data fixes) go in their own `if (from < N)`
          // block.
          for (final step in columnsAddedInVersion.entries) {
            if (from >= step.key) continue;
            for (final entry in step.value.entries) {
              final table = allTables.firstWhere((t) => t.actualTableName == entry.key);
              for (final name in entry.value) {
                await m.addColumn(table, table.$columns.firstWhere((c) => c.name == name));
              }
            }
          }
          //
          // CRITICAL when adding a column to an EXISTING table (tables.dart):
          //   1. The column MUST declare withDefault(...)/clientDefault (or be
          //      nullable) — SQLite's ALTER TABLE ADD COLUMN cannot add a NOT
          //      NULL column without a default.
          //   2. Bump schemaVersion above and add the column to
          //      columnsAddedInVersion under the new version IN THE SAME
          //      change. Drift selects the full explicit column list, so an
          //      installed app that skips this step crashes on launch with
          //      "no such column" — onCreate hides this because it always
          //      builds the full current schema. Backup validation relies on
          //      the same map to tell missing (migratable) columns apart.
          //   3. Steps must accumulate (if (from < N)), never replace an
          //      earlier step.
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          // Performance (BL-064). Per-connection settings, so no schema bump.
          // WAL: commits append to the -wal file instead of rewriting pages,
          // and reads (the watch streams) don't block writes. synchronous =
          // NORMAL is the recommended pairing: durable across app crashes, only
          // the last commits can be lost on a power cut. Backups already
          // checkpoint the WAL before copying (BackupService.createBackup), and
          // auto-backups/restore carry the -wal/-shm sidecars.
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA synchronous = NORMAL');
          await customStatement('PRAGMA temp_store = MEMORY');
          // Indexes added after an install was created (IF NOT EXISTS: no-op
          // otherwise).
          await _createIndexes(this);
        },
      );
}

/// Table definitions only, for [AppDatabase._readCurrentColumns]. Its own
/// class so drift's debug "created AppDatabase multiple times" check, which
/// counts instances per runtimeType, ignores it.
class _SchemaProbe extends AppDatabase {
  _SchemaProbe() : super(NativeDatabase.memory());
}

/// Drops every table and rebuilds the current schema from scratch (seed +
/// indexes included), i.e. exactly what [AppDatabase.migration]'s onCreate
/// does for a fresh install. Destructive by design: only for upgrade paths
/// that cannot preserve data, and only ever called *after*
/// [BackupService.createAutoBackup] has snapshotted the old file.
Future<void> _rebuildFromScratch(AppDatabase db, Migrator m) async {
  await db.customStatement('PRAGMA foreign_keys = OFF');
  for (final table in db.allTables) {
    await m.deleteTable(table.actualTableName);
  }
  await m.createAll();
  await _seedDefaults(db);
  await _createIndexes(db);
  await _createRecurringIndexes(db);
  await db.customStatement('PRAGMA foreign_keys = ON');
}

/// Indexes on the hottest `expenses` query paths (R3): every analytics/listing
/// query filters by `date` and/or `category_id`, which were full table scans.
/// Declared here (not via table annotations) so no codegen step is needed and
/// the same statements serve onCreate, the dev rebuild and beforeOpen. All
/// use IF NOT EXISTS, so adding one needs no schemaVersion bump: beforeOpen
/// creates it on existing installs.
Future<void> _createIndexes(AppDatabase db) async {
  await db.customStatement('CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date)');
  await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category_id)');
  // Matches ExpenseRepository's total order (date, created_at, id), so the
  // paginated list reads it in index order with no temp B-tree sort and the
  // keyset cursor seeks straight to the next page (BL-065).
  await db.customStatement('CREATE INDEX IF NOT EXISTS idx_expenses_order '
      'ON expenses(date DESC, created_at DESC, id DESC)');
}

/// Indexes on the recurring feature's hot paths (feature 3.13): the
/// materializer scans active templates by `next_date`, and the pending inbox
/// lists occurrences by `due_date`.
Future<void> _createRecurringIndexes(AppDatabase db) async {
  await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_recurrings_next ON recurrings(next_date)');
  await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_recurring_occ_due ON recurring_occurrences(due_date)');
}

/// Default rows of a fresh install, written in a single batch (one
/// transaction, prepared statements reused) instead of ~90 sequential inserts
/// (BL-066).
Future<void> _seedDefaults(AppDatabase db) => db.batch((batch) => _queueDefaults(db, batch));

void _queueDefaults(AppDatabase db, Batch batch) {
  batch.insert(db.profile, const ProfileCompanion());

  final tagGroupIds = <String, String>{};
  const tagGroupKeys = [
    'tag_group.ungrouped',
    'tag_group.social_context',
    'tag_group.motivation',
    'tag_group.life_moment',
  ];
  for (var i = 0; i < tagGroupKeys.length; i++) {
    final id = _uuid.v4();
    tagGroupIds[tagGroupKeys[i]] = id;
    batch.insert(db.tagGroups, TagGroupsCompanion.insert(id: id, name: tagGroupKeys[i], position: Value(i)));
  }

  const tagsByGroup = {
    'tag_group.social_context': [
      'tag.alone',
      'tag.partner',
      'tag.family',
      'tag.friends',
      'tag.work',
    ],
    'tag_group.motivation': [
      'tag.leisure',
      'tag.necessity',
      'tag.whim',
      'tag.gift',
      'tag.investment',
    ],
    'tag_group.life_moment': [
      'tag.vacation',
      'tag.weekend',
      'tag.routine',
      'tag.unexpected',
    ],
  };
  for (final entry in tagsByGroup.entries) {
    final groupId = tagGroupIds[entry.key]!;
    for (var i = 0; i < entry.value.length; i++) {
      batch.insert(
        db.tags,
        TagsCompanion.insert(
          id: _uuid.v4(),
          tagGroupId: groupId,
          name: entry.value[i],
          isDefault: const Value(true),
          position: Value(i),
        ),
      );
    }
  }

  // Default category trees, one forest per transaction type (rule: categories
  // per transaction type). Names are i18n keys resolved at render time while
  // the category keeps is_default = true (see displayNameFor). Nested via
  // parentId (up to 3 levels: category > subcategory > subsubcategory). A
  // parent category holds its own label under the reserved `._` key so the
  // node can be both a JSON map (of children) and carry a displayable string.
  const categoryForest = {
    'expense': [
      _Cat('category.expense.food._', [
        _Cat('category.expense.food.groceries'),
        _Cat('category.expense.food.eating_out'),
      ]),
      _Cat('category.expense.hygiene'),
      _Cat('category.expense.home._', [
        _Cat('category.expense.home.internet'),
        _Cat('category.expense.home.furniture'),
        _Cat('category.expense.home.kitchen'),
        _Cat('category.expense.home.bathroom'),
        _Cat('category.expense.home.electricity'),
        _Cat('category.expense.home.gas'),
        _Cat('category.expense.home.water'),
        _Cat('category.expense.home.rent'),
        _Cat('category.expense.home.cleaning'),
        _Cat('category.expense.home.others'),
      ]),
      _Cat('category.expense.sports._', [
        _Cat('category.expense.sports.climbing._', [
          _Cat('category.expense.sports.climbing.gym'),
          _Cat('category.expense.sports.climbing.gear'),
          _Cat('category.expense.sports.climbing.events'),
        ]),
        _Cat('category.expense.sports.gym'),
        _Cat('category.expense.sports.pool'),
        _Cat('category.expense.sports.others'),
      ]),
      _Cat('category.expense.clothes._', [
        _Cat('category.expense.clothes.clothing._', [
          _Cat('category.expense.clothes.clothing.clothing'),
          _Cat('category.expense.clothes.clothing.shoes'),
          _Cat('category.expense.clothes.clothing.accessories'),
        ]),
        _Cat('category.expense.clothes.laundry'),
      ]),
      _Cat('category.expense.health._', [
        _Cat('category.expense.health.general'),
        _Cat('category.expense.health.medical_tests'),
        _Cat('category.expense.health.medicines'),
        _Cat('category.expense.health.psychologist'),
        _Cat('category.expense.health.physiotherapy'),
      ]),
      _Cat('category.expense.transport._', [
        _Cat('category.expense.transport.car'),
        _Cat('category.expense.transport.public_transport'),
        _Cat('category.expense.transport.taxi'),
      ]),
      _Cat('category.expense.others'),
    ],
    'income': [
      _Cat('category.income.salary'),
      _Cat('category.income.extra'),
      _Cat('category.income.others'),
    ],
    'refund': [
      _Cat('category.refund.purchase'),
      _Cat('category.refund.deposit'),
      _Cat('category.refund.bizum'),
      _Cat('category.refund.others'),
    ],
    'ahorro': [
      _Cat('category.savings.emergency_fund'),
      _Cat('category.savings.regular'),
      _Cat('category.savings.monthly_extra'),
      _Cat('category.savings.others'),
    ],
  };
  for (final entry in categoryForest.entries) {
    for (var i = 0; i < entry.value.length; i++) {
      _insertCategoryNode(db, batch, type: entry.key, node: entry.value[i], position: i);
    }
  }

  const paymentMethods = [
    'payment.card',
    'payment.cash',
  ];
  for (var i = 0; i < paymentMethods.length; i++) {
    batch.insert(
      db.paymentMethods,
      PaymentMethodsCompanion.insert(
        id: _uuid.v4(),
        name: paymentMethods[i],
        isDefault: const Value(true),
        position: Value(i),
      ),
    );
  }
}

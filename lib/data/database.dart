import 'package:drift/drift.dart';
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
Future<void> _insertCategoryNode(
  AppDatabase db, {
  required String type,
  String? parentId,
  required _Cat node,
  required int position,
}) async {
  final id = _uuid.v4();
  await db.into(db.categories).insert(
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
    await _insertCategoryNode(db, type: type, parentId: id, node: node.children[i], position: i);
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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor, BackupService? backupService])
      : _backupService = backupService ?? BackupService(),
        super(executor ?? _openConnection());

  final BackupService _backupService;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'despeses');
  }

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaults(this);
          await _createIndexes(this);
          await _createRecurringIndexes(this);
        },
        onUpgrade: (m, from, to) async {
          // Safety net first: copy the current DB (main file + WAL sidecars)
          // before touching it, so a buggy migration step — or the dev reseed
          // below — can never destroy data unrecoverably. Never throws.
          await _backupService.createAutoBackup();

          if (_devReseedOnUpgrade) {
            // DEV-ONLY: wipe everything and reseed. Guarded by a const that is
            // false in real builds (see _devReseedOnUpgrade).
            await customStatement('PRAGMA foreign_keys = OFF');
            for (final table in allTables) {
              await m.deleteTable(table.actualTableName);
            }
            await m.createAll();
            await _seedDefaults(this);
            await _createIndexes(this);
            await customStatement('PRAGMA foreign_keys = ON');
            return;
          }

          // Data-preserving migrations. Add one `if (from < N)` block per
          // schema bump, e.g.:
          //   if (from < 8) await m.addColumn(expenses, expenses.someColumn);
          //   if (from < 9) await m.createTable(recurring);
          // v7 adds the analytics/listing indexes on `expenses` (R3).
          if (from < 7) await _createIndexes(this);
          // v8 adds recurring-transaction tables (feature 3.13): template,
          // its tags, and the pending-occurrence inbox. Additive only.
          if (from < 8) {
            await m.createTable(recurrings);
            await m.createTable(recurringTags);
            await m.createTable(recurringOccurrences);
            await _createRecurringIndexes(this);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

/// Indexes on the hottest `expenses` query paths (R3): every analytics/listing
/// query filters by `date` and/or `category_id`, which were full table scans.
/// Declared here (not via table annotations) so no codegen step is needed and
/// the same statements serve both onCreate and the v7 migration.
Future<void> _createIndexes(AppDatabase db) async {
  await db.customStatement('CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date)');
  await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category_id)');
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

Future<void> _seedDefaults(AppDatabase db) async {
  await db.into(db.profile).insert(const ProfileCompanion());

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
    await db.into(db.tagGroups).insert(
          TagGroupsCompanion.insert(id: id, name: tagGroupKeys[i], position: Value(i)),
        );
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
      await db.into(db.tags).insert(
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
      await _insertCategoryNode(db, type: entry.key, node: entry.value[i], position: i);
    }
  }

  const paymentMethods = [
    'payment.cash',
    'payment.credit_card',
    'payment.debit_card',
    'payment.transfer',
  ];
  for (var i = 0; i < paymentMethods.length; i++) {
    await db.into(db.paymentMethods).insert(
          PaymentMethodsCompanion.insert(
            id: _uuid.v4(),
            name: paymentMethods[i],
            isDefault: const Value(true),
            position: Value(i),
          ),
        );
  }
}

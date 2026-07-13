import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import 'tables.dart';

part 'database.g.dart';

const _uuid = Uuid();

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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'despeses');
  }

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaults(this);
        },
        // Dev app: schema v2 introduces per-type category trees + the `ahorro`
        // transaction type. Existing data is not preserved (reseed) — drop all
        // tables and recreate from scratch. Alternatively delete the DB file.
        onUpgrade: (m, from, to) async {
          await customStatement('PRAGMA foreign_keys = OFF');
          for (final table in allTables) {
            await m.deleteTable(table.actualTableName);
          }
          await m.createAll();
          await _seedDefaults(this);
          await customStatement('PRAGMA foreign_keys = ON');
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
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
  // per transaction type). All roots are leaves for now (flat).
  const categoriesByType = {
    'expense': [
      'category.food',
      'category.transport',
      'category.housing',
      'category.leisure',
      'category.health',
      'category.clothing',
      'category.education',
    ],
    'income': [
      'category.income.salary',
      'category.income.extra',
      'category.income.gift',
      'category.income.investment',
      'category.income.other',
    ],
    'refund': [
      'category.refund.purchase_return',
      'category.refund.deposit',
      'category.refund.other',
    ],
    'ahorro': [
      'category.savings.emergency',
      'category.savings.retirement',
      'category.savings.goal',
      'category.savings.other',
    ],
  };
  for (final entry in categoriesByType.entries) {
    for (var i = 0; i < entry.value.length; i++) {
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: _uuid.v4(),
              name: entry.value[i],
              type: Value(entry.key),
              isDefault: const Value(true),
              position: Value(i),
            ),
          );
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

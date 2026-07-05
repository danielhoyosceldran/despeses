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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaults(this);
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

  const rootCategories = [
    'category.food',
    'category.transport',
    'category.housing',
    'category.leisure',
    'category.health',
    'category.clothing',
    'category.education',
  ];
  for (var i = 0; i < rootCategories.length; i++) {
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: _uuid.v4(),
            name: rootCategories[i],
            isDefault: const Value(true),
            position: Value(i),
          ),
        );
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

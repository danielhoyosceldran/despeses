import 'package:drift/drift.dart';

class Profile extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get language => text().withDefault(const Constant('en'))();
  TextColumn get currency => text().withDefault(const Constant('EUR'))();
  TextColumn get theme => text().withDefault(const Constant('light'))();
  BoolColumn get hapticsEnabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class TagGroups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 100)();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {name},
      ];
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get tagGroupId => text().customConstraint(
      'NOT NULL REFERENCES tag_groups(id) ON DELETE RESTRICT')();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().withLength(max: 50).nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {name},
      ];
}

class Categories extends Table {
  TextColumn get id => text()();
  // Which transaction-type tree this category belongs to: each type has its own
  // forest (rule: categories per transaction type).
  TextColumn get type => text()
      .customConstraint(
          "NOT NULL DEFAULT 'expense' CHECK (type IN ('expense', 'income', 'refund', 'ahorro'))")
      .clientDefault(() => 'expense')();
  TextColumn get parentId => text()
      .nullable()
      .customConstraint('REFERENCES categories(id) ON DELETE CASCADE')();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().withLength(max: 50).nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {type, parentId, name},
      ];
}

class PaymentMethods extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get icon => text().withLength(max: 50).nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {name},
      ];
}

class Events extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 150)();
  TextColumn get description => text().withLength(max: 500).nullable()();
  DateTimeColumn get startsAt => dateTime().nullable()();
  DateTimeColumn get endsAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {name},
      ];
}

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 150)();
  TextColumn get description => text().withLength(max: 500).nullable()();
  DateTimeColumn get startsAt => dateTime().nullable()();
  DateTimeColumn get endsAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {name},
      ];
}

class Expenses extends Table {
  TextColumn get id => text()();
  IntColumn get amount => integer().customConstraint('NOT NULL CHECK (amount > 0)')();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  TextColumn get type =>
      text().customConstraint("NOT NULL CHECK (type IN ('expense', 'income', 'refund', 'ahorro'))")();
  DateTimeColumn get date => dateTime()();
  TextColumn get description => text().withLength(max: 300).nullable()();
  TextColumn get notes => text().withLength(max: 1000).nullable()();
  TextColumn get categoryId => text()
      .nullable()
      .customConstraint('REFERENCES categories(id) ON DELETE SET NULL')();
  TextColumn get paymentMethodId => text()
      .nullable()
      .customConstraint('REFERENCES payment_methods(id) ON DELETE SET NULL')();
  TextColumn get eventId => text()
      .nullable()
      .customConstraint('REFERENCES events(id) ON DELETE SET NULL')();
  TextColumn get projectId => text()
      .nullable()
      .customConstraint('REFERENCES projects(id) ON DELETE SET NULL')();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ExpenseTags extends Table {
  TextColumn get expenseId =>
      text().customConstraint('NOT NULL REFERENCES expenses(id) ON DELETE CASCADE')();
  TextColumn get tagId =>
      text().customConstraint('NOT NULL REFERENCES tags(id) ON DELETE CASCADE')();

  @override
  Set<Column> get primaryKey => {expenseId, tagId};
}

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 150)();
  TextColumn get categoryId => text()
      .nullable()
      .customConstraint('REFERENCES categories(id) ON DELETE CASCADE')();
  TextColumn get tagId =>
      text().nullable().customConstraint('REFERENCES tags(id) ON DELETE CASCADE')();
  TextColumn get projectId => text()
      .nullable()
      .customConstraint('REFERENCES projects(id) ON DELETE CASCADE')();
  TextColumn get eventId =>
      text().nullable().customConstraint('REFERENCES events(id) ON DELETE CASCADE')();
  IntColumn get amount => integer().customConstraint('NOT NULL CHECK (amount > 0)')();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  TextColumn get budgetType => text().customConstraint(
      "NOT NULL CHECK (budget_type IN ('months', 'range', 'total'))")();
  TextColumn get months => text().nullable()();
  TextColumn get startsMonth => text().nullable()();
  TextColumn get endsMonth => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

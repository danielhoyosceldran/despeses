import 'package:drift/drift.dart';

class Profile extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get language => text().withDefault(const Constant('en'))();
  TextColumn get currency => text().withDefault(const Constant('EUR'))();
  TextColumn get theme => text().withDefault(const Constant('light'))();
  BoolColumn get hapticsEnabled => boolean().withDefault(const Constant(true))();
  /// Feedback intensity: 0 = soft, 1 = medium (default), 2 = strong.
  IntColumn get hapticsStrength => integer().withDefault(const Constant(1))();
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

/// A recurring-transaction template (feature 3.13). Holds the same payload as
/// an [Expenses] row plus a schedule. It never appears in listings/analytics
/// itself; instead the materializer turns due dates into [RecurringOccurrences]
/// that the user confirms into real [Expenses]. Amount is stored positive; sign
/// is derived from [type] like everywhere else.
class Recurrings extends Table {
  TextColumn get id => text()();
  IntColumn get amount => integer().customConstraint('NOT NULL CHECK (amount > 0)')();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  TextColumn get type =>
      text().customConstraint("NOT NULL CHECK (type IN ('expense', 'income', 'refund', 'ahorro'))")();
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
  TextColumn get frequency => text()
      .customConstraint("NOT NULL CHECK (frequency IN ('monthly', 'weekly', 'yearly'))")();
  // First occurrence date; also the monthly day-of-month / yearly month+day
  // anchor used when advancing [nextDate].
  DateTimeColumn get startDate => dateTime()();
  // Next date this template is due to fire. Advanced by the materializer.
  DateTimeColumn get nextDate => dateTime()();
  // Optional inclusive stop date. When [nextDate] passes it, the template is
  // deactivated.
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  // Bookkeeping: when the materializer last produced an occurrence.
  DateTimeColumn get lastPostedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class RecurringTags extends Table {
  TextColumn get recurringId =>
      text().customConstraint('NOT NULL REFERENCES recurrings(id) ON DELETE CASCADE')();
  TextColumn get tagId =>
      text().customConstraint('NOT NULL REFERENCES tags(id) ON DELETE CASCADE')();

  @override
  Set<Column> get primaryKey => {recurringId, tagId};
}

/// A materialized due occurrence awaiting the user's confirmation (the pending
/// inbox). Scalar fields are a snapshot taken when the occurrence was
/// materialized, so a later edit to the template does not silently change what
/// was due. Confirming one creates a real [Expenses] row (copying the
/// template's current tags) and deletes the occurrence; skipping just deletes
/// it. The `{recurringId, dueDate}` unique key makes materialization idempotent.
class RecurringOccurrences extends Table {
  TextColumn get id => text()();
  TextColumn get recurringId =>
      text().customConstraint('NOT NULL REFERENCES recurrings(id) ON DELETE CASCADE')();
  DateTimeColumn get dueDate => dateTime()();
  IntColumn get amount => integer().customConstraint('NOT NULL CHECK (amount > 0)')();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  TextColumn get type =>
      text().customConstraint("NOT NULL CHECK (type IN ('expense', 'income', 'refund', 'ahorro'))")();
  TextColumn get description => text().withLength(max: 300).nullable()();
  TextColumn get notes => text().withLength(max: 1000).nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get paymentMethodId => text().nullable()();
  TextColumn get eventId => text().nullable()();
  TextColumn get projectId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {recurringId, dueDate},
      ];
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
      "NOT NULL CHECK (budget_type IN ('monthly', 'range'))")();
  // Range budgets only. `monthly` budgets recur every month and leave both null.
  TextColumn get startsMonth => text().nullable()();
  TextColumn get endsMonth => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// A savings goal (feature 3.14). Reuses the existing `ahorro` transaction type
/// and savings category trees: progress is the running sum of every `ahorro`
/// transaction filed under [categoryId] (and its descendants), so a goal fills
/// up as the user records savings — the inverse read of a [Budgets] limit.
/// Unlike a budget it has no period window; the sum is cumulative from the
/// first-ever savings transaction. [targetAmount] is the meta (positive cents);
/// [deadline] is optional and only powers the "needed per month" pace hint.
class SavingsGoals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 150)();
  // The savings category whose `ahorro` transactions accrue toward this goal.
  // Cascades: deleting the category removes the goal (same as budgets).
  TextColumn get categoryId => text()
      .customConstraint('NOT NULL REFERENCES categories(id) ON DELETE CASCADE')();
  IntColumn get targetAmount => integer().customConstraint('NOT NULL CHECK (target_amount > 0)')();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  DateTimeColumn get deadline => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

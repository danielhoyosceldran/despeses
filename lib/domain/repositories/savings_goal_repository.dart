import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import 'analytics/analytics_math.dart';
import 'category_repository.dart';

const _uuid = Uuid();

/// Thrown by [SavingsGoalRepository.create] when another goal already tracks
/// the same category, one of its ancestors or one of its descendants: progress
/// includes descendants, so both goals would count the same savings.
class GoalCategoryInUseException implements Exception {
  const GoalCategoryInUseException(this.conflictingGoalName);

  final String conflictingGoalName;
}

/// Progress toward a [SavingsGoal] plus the pace needed to hit its deadline.
class GoalProgress {
  const GoalProgress({
    required this.saved,
    required this.target,
    this.monthsLeft,
    this.perMonthNeeded,
  });

  final int saved;
  final int target;

  /// Whole months from now until the deadline (>= 0), or null when the goal has
  /// no deadline.
  final int? monthsLeft;

  /// Cents still to save each remaining month to reach [target] on time, or null
  /// when there is no deadline. 0 once the goal is already met.
  final int? perMonthNeeded;

  double get ratio => target == 0 ? 0 : (saved / target).clamp(0.0, 1.0);
  bool get reached => saved >= target;
  int get remaining => (target - saved).clamp(0, target);
}

/// Savings goals (feature 3.14). A goal tracks how much `ahorro` has been filed
/// under a savings category (and its descendants) against a target amount —
/// the mirror of a budget's spend-vs-limit. Progress is cumulative from the
/// day the goal was created (earlier savings belong to no goal), so it reuses [CategoryRepository.descendantIds]
/// and sums the `ahorro` type via [sumOfType].
class SavingsGoalRepository {
  SavingsGoalRepository(this._db, this._categories);

  final AppDatabase _db;
  final CategoryRepository _categories;

  Future<List<SavingsGoal>> listAll() {
    return (_db.select(_db.savingsGoals)..orderBy([(g) => OrderingTerm.asc(g.createdAt)])).get();
  }

  Future<SavingsGoal?> byId(String id) {
    return (_db.select(_db.savingsGoals)..where((g) => g.id.equals(id))).getSingleOrNull();
  }

  /// Throws [GoalCategoryInUseException] if another goal's category overlaps
  /// [categoryId]'s tree (see [goalOverlapping]). [now] (the creation time) is
  /// injectable for tests.
  Future<String> create({
    required String name,
    required String categoryId,
    required int targetCents,
    required String currency,
    DateTime? deadline,
    DateTime? now,
  }) async {
    final id = _uuid.v4();
    await _db.transaction(() async {
      final conflict = await goalOverlapping(categoryId);
      if (conflict != null) throw GoalCategoryInUseException(conflict.name);
      await _db.into(_db.savingsGoals).insert(
            SavingsGoalsCompanion.insert(
              id: id,
              name: name,
              categoryId: categoryId,
              targetAmount: targetCents,
              currency: currency,
              deadline: Value(deadline),
              createdAt: now == null ? const Value.absent() : Value(now),
            ),
          );
    });
    return id;
  }

  /// An existing goal whose category is [categoryId] itself, an ancestor or a
  /// descendant of it — i.e. one that would count the same savings — or null.
  Future<SavingsGoal?> goalOverlapping(String categoryId) async {
    // Fresh parent links (not the memoized descendant map, which is cleared
    // asynchronously and could miss a category created just before).
    final parentOf = {for (final c in await _categories.listAll()) c.id: c.parentId};
    Set<String> selfAndAncestors(String id) {
      final ids = <String>{};
      String? cursor = id;
      while (cursor != null && ids.add(cursor)) {
        cursor = parentOf[cursor];
      }
      return ids;
    }

    final lineage = selfAndAncestors(categoryId);
    for (final goal in await listAll()) {
      // Same or ancestor: goal's category is in our lineage. Descendant: our
      // category is in the goal category's lineage.
      if (lineage.contains(goal.categoryId) || selfAndAncestors(goal.categoryId).contains(categoryId)) {
        return goal;
      }
    }
    return null;
  }

  /// Edits a goal. The linked category and currency are locked after creation
  /// (like a budget's dimension), so only name/target/deadline can change.
  Future<void> update(
    String id, {
    String? name,
    int? targetCents,
    DateTime? deadline,
    bool clearDeadline = false,
  }) async {
    await (_db.update(_db.savingsGoals)..where((g) => g.id.equals(id))).write(
      SavingsGoalsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        targetAmount: targetCents == null ? const Value.absent() : Value(targetCents),
        deadline: clearDeadline ? const Value(null) : (deadline == null ? const Value.absent() : Value(deadline)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.savingsGoals)..where((g) => g.id.equals(id))).go();
  }

  /// Cumulative `ahorro` saved under the goal's category (+ descendants), in the
  /// goal's currency, from the day the goal was created: savings recorded
  /// before it existed don't count toward it (a new goal starts empty).
  Future<int> calculateSaved(SavingsGoal goal) async {
    final ids = {goal.categoryId, ...await _categories.descendantIds(goal.categoryId)};
    final created = goal.createdAt;
    final from = DateTime(created.year, created.month, created.day);
    final rows = await (_db.select(_db.expenses)
          ..where((e) => e.currency.equals(goal.currency))
          ..where((e) => e.date.isBiggerOrEqualValue(from))
          // Scheduled (future-dated) rows don't count until their day.
          ..where((e) => e.date.isSmallerThanValue(scheduledFrom()))
          ..where((e) => e.type.equals('ahorro'))
          ..where((e) => e.categoryId.isIn(ids)))
        .get();
    return sumOfType(rows, 'ahorro');
  }

  /// Full progress for a goal, including deadline pace when set. [now] is
  /// injectable for tests.
  Future<GoalProgress> calculateProgress(SavingsGoal goal, {DateTime? now}) async {
    final saved = await calculateSaved(goal);
    if (goal.deadline == null) {
      return GoalProgress(saved: saved, target: goal.targetAmount);
    }
    final today = now ?? DateTime.now();
    final monthsLeft = _monthsBetween(today, goal.deadline!);
    final remaining = (goal.targetAmount - saved).clamp(0, goal.targetAmount);
    // Divide across the remaining months, counting the current month (so a
    // deadline this month still asks for the whole remainder). Past-due goals
    // ask for the whole remainder now.
    final divisor = monthsLeft < 1 ? 1 : monthsLeft;
    final perMonth = remaining == 0 ? 0 : (remaining / divisor).ceil();
    return GoalProgress(
      saved: saved,
      target: goal.targetAmount,
      monthsLeft: monthsLeft,
      perMonthNeeded: perMonth,
    );
  }

  /// Whole months from [from] to [to], counting the current month, floored at 0.
  /// E.g. same month → 1, next month → 2, a past date → 0.
  static int _monthsBetween(DateTime from, DateTime to) {
    final months = (to.year - from.year) * 12 + (to.month - from.month) + 1;
    return months < 0 ? 0 : months;
  }
}

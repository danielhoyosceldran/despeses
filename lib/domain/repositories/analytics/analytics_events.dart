import '../../../data/database.dart';
import 'analytics_category.dart';
import 'analytics_math.dart';

/// Event/Project spend analytics (Analytics › Eventos y Proyectos, section A6).
/// A "scope" is exactly one of an event or a project id.
class EventAnalytics {
  EventAnalytics(this._db);

  final AppDatabase _db;

  Future<List<Expense>> _scopeExpenses({String? eventId, String? projectId}) {
    final q = _db.select(_db.expenses);
    if (eventId != null) {
      q.where((e) => e.eventId.equals(eventId));
    } else if (projectId != null) {
      q.where((e) => e.projectId.equals(projectId));
    }
    return q.get();
  }

  /// A6.1 — signed total cost of the event/project (expense − refund).
  Future<int> totalCost({String? eventId, String? projectId}) async {
    return signedSpend(await _scopeExpenses(eventId: eventId, projectId: projectId));
  }

  /// A6.3 — cost per day = total / duration in days (inclusive). Returns null
  /// when the entity has no start/end dates.
  Future<double?> costPerDay({
    required DateTime? startsAt,
    required DateTime? endsAt,
    String? eventId,
    String? projectId,
  }) async {
    if (startsAt == null || endsAt == null) return null;
    final days = endsAt.difference(startsAt).inDays + 1;
    if (days <= 0) return null;
    final total = await totalCost(eventId: eventId, projectId: projectId);
    return total / days;
  }

  /// A6.4 — spend by (expense) category within the event/project.
  Future<List<CategorySlice>> categoryBreakdown({String? eventId, String? projectId}) async {
    final expenses = (await _scopeExpenses(eventId: eventId, projectId: projectId))
        .where((e) => e.type == 'expense')
        .toList();
    final byCategory = <String?, int>{};
    for (final e in expenses) {
      byCategory[e.categoryId] = (byCategory[e.categoryId] ?? 0) + e.amount;
    }
    return [
      for (final entry in byCategory.entries)
        if (entry.key != null && entry.value != 0)
          CategorySlice(categoryId: entry.key!, amountCents: entry.value),
    ];
  }

  /// A6.5 — cumulative spend over time (sorted by date).
  Future<List<(DateTime, int)>> timeline({String? eventId, String? projectId}) async {
    final expenses = await _scopeExpenses(eventId: eventId, projectId: projectId);
    expenses.sort((a, b) => a.date.compareTo(b.date));
    var acc = 0;
    return [
      for (final e in expenses)
        (e.date, acc += (e.type == 'refund' ? -e.amount : (e.type == 'expense' ? e.amount : 0))),
    ];
  }

  /// A6.6 — data-quality: expenses assigned to the event but dated outside
  /// `[startsAt, endsAt]`.
  Future<List<Expense>> outOfRange({
    required String eventId,
    required DateTime? startsAt,
    required DateTime? endsAt,
  }) async {
    if (startsAt == null || endsAt == null) return const [];
    final expenses = await _scopeExpenses(eventId: eventId);
    return expenses.where((e) => e.date.isBefore(startsAt) || e.date.isAfter(endsAt)).toList();
  }
}

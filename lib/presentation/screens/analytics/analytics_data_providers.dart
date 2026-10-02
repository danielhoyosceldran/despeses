import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../../domain/repositories/analytics/analytics_category.dart';
import '../../../domain/repositories/analytics/analytics_math.dart';
import '../../../domain/repositories/analytics/analytics_tags.dart';
import '../../../domain/repositories/budget_repository.dart';

/// Analytics section data, keyed by the section's inputs (month/currency/…).
/// Moving the per-section `_load` off `build` and into a `FutureProvider.family`
/// (R1) means Riverpod caches each result by its arguments: a rebuild
/// with the same arguments — e.g. the ~60fps rebuilds while dragging the
/// section FAB — is a cache hit, not a fresh query. Only a real input change
/// (month swipe, drill, event switch) runs a query, exactly once.
///
/// These are `autoDispose` + [_keepAliveFor] rather than plain `autoDispose`:
/// the Analytics screen stays mounted across tabs (IndexedStack), and the
/// month PageView lets the user swipe through unlimited months (R26), so a
/// bare non-autoDispose family would cache every visited month forever. Each
/// entry instead survives for [_sectionCacheTtl] after its last watcher drops
/// (e.g. leaving the Analytics tab or swiping to another month) and is then
/// evicted, capping memory while still surviving quick tab switches. Freshness
/// after a mutation on another tab is handled by [invalidateAnalyticsSections],
/// which the screen calls when the Analytics tab regains focus.

const _sectionCacheTtl = Duration(minutes: 10);

/// Keeps an `autoDispose` provider entry alive for [_sectionCacheTtl] after
/// its last listener unsubscribes, instead of disposing immediately.
void _keepAliveFor(Ref ref, [Duration ttl = _sectionCacheTtl]) {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  ref.onCancel(() => timer = Timer(ttl, link.close));
  ref.onResume(() => timer?.cancel());
}

typedef MonthCurrency = ({DateTime month, String currency});
typedef CategoryArgs = ({DateTime month, String currency, String? parentId});
typedef EventArgs = ({String eventId, DateTime? startsAt, DateTime? endsAt, String currency});

/// Every section family provider, so the screen can drop cached results in one
/// call when the tab regains focus (data may have changed elsewhere).
void invalidateAnalyticsSections(WidgetRef ref) {
  developer.log('invalidating all analytics section providers', name: 'Analytics');
  ref.invalidate(categorySectionProvider);
  ref.invalidate(tagSectionProvider);
  ref.invalidate(budgetSectionProvider);
  ref.invalidate(eventListProvider);
  ref.invalidate(eventSectionProvider);
}

/// Category ------------------------------------------------------------------

class CategorySectionData {
  CategorySectionData(this.slices, this.labels, this.hasChildren, this.categoryById, this.translations);
  final List<CategorySlice> slices;
  final Map<String, String> labels;
  final Map<String, bool> hasChildren;
  final Map<String, Category> categoryById;
  final Translations translations;
}

final categorySectionProvider =
    FutureProvider.autoDispose.family<CategorySectionData, CategoryArgs>((ref, a) async {
  _keepAliveFor(ref);
  final analytics = ref.watch(categoryAnalyticsProvider);
  final translations = await ref.watch(translationsProvider.future);
  final allCategories = await ref.watch(referenceDataCacheProvider).categories();
  final slices = await analytics.breakdown(
    DateRange.month(a.month),
    parentId: a.parentId,
    type: 'expense',
    currency: a.currency,
  );
  final byId = {for (final c in allCategories) c.id: c};
  final labels = <String, String>{};
  final hasChildren = <String, bool>{};
  for (final s in slices) {
    final c = byId[s.categoryId];
    if (c == null) continue;
    labels[s.categoryId] = displayNameFor(translations, name: c.name, isDefault: c.isDefault);
    hasChildren[s.categoryId] = allCategories.any((x) => x.parentId == s.categoryId);
  }
  return CategorySectionData(slices, labels, hasChildren, byId, translations);
});

/// Tags ----------------------------------------------------------------------

class TagSectionData {
  TagSectionData(this.slices, this.labels, this.translations);
  final List<TagSlice> slices;
  final Map<String, String> labels;
  final Translations translations;
}

final tagSectionProvider =
    FutureProvider.autoDispose.family<TagSectionData, MonthCurrency>((ref, a) async {
  _keepAliveFor(ref);
  final analytics = ref.watch(tagAnalyticsProvider);
  final translations = await ref.watch(translationsProvider.future);
  final allTags = await ref.watch(referenceDataCacheProvider).tags();
  final slices = await analytics.byTag(DateRange.month(a.month), a.currency);
  final byId = {for (final t in allTags) t.id: t};
  final labels = {
    for (final s in slices)
      if (byId[s.tagId] != null)
        s.tagId: displayNameFor(translations, name: byId[s.tagId]!.name, isDefault: byId[s.tagId]!.isDefault),
  };
  return TagSectionData(slices, labels, translations);
});

/// Budgets -------------------------------------------------------------------

class BudgetRowData {
  BudgetRowData({
    required this.name,
    required this.spent,
    required this.limit,
    required this.spentFraction,
    required this.overPace,
    required this.projected,
  });
  final String name;
  final int spent;
  final int limit;
  final double spentFraction;
  final bool overPace;
  final int? projected;
}

final budgetSectionProvider =
    FutureProvider.autoDispose.family<List<BudgetRowData>, MonthCurrency>((ref, a) async {
  _keepAliveFor(ref);
  final repo = ref.watch(budgetRepositoryProvider);
  final analytics = ref.watch(budgetAnalyticsProvider);
  final monthKey = monthKeyOf(DateTime(a.month.year, a.month.month));
  final active = (await repo.listAll()).where((b) => repo.isActiveForMonth(b, monthKey)).toList();
  final rows = <BudgetRowData>[];
  for (final b in active) {
    final pace = await analytics.pace(b);
    rows.add(BudgetRowData(
      name: b.name,
      spent: pace.spentCents,
      limit: pace.limitCents,
      spentFraction: pace.spentFraction,
      overPace: pace.overPace,
      projected: pace.projectedEndCents,
    ));
  }
  return rows;
});

/// Events --------------------------------------------------------------------

final eventListProvider = FutureProvider<List<Event>>(
    (ref) => ref.watch(referenceDataCacheProvider).events());

class EventSectionData {
  EventSectionData(this.total, this.savings, this.perDay, this.timeline, this.outOfRange);
  final int total;

  /// Savings set aside under the event — shown apart from [total].
  final int savings;
  final double? perDay;
  final List<(DateTime, int)> timeline;
  final int outOfRange;
}

final eventSectionProvider =
    FutureProvider.autoDispose.family<EventSectionData, EventArgs>((ref, a) async {
  _keepAliveFor(ref);
  final ev = ref.watch(eventAnalyticsProvider);
  final total = await ev.totalCost(eventId: a.eventId);
  final savings = await ev.savings(eventId: a.eventId);
  final perDay = await ev.costPerDay(startsAt: a.startsAt, endsAt: a.endsAt, eventId: a.eventId);
  final timeline = await ev.timeline(eventId: a.eventId);
  final oor = await ev.outOfRange(eventId: a.eventId, startsAt: a.startsAt, endsAt: a.endsAt);
  return EventSectionData(total, savings, perDay, timeline, oor.length);
});

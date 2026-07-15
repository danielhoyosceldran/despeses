import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../../domain/repositories/analytics/analytics_behavior.dart';
import '../../../domain/repositories/analytics/analytics_cashflow.dart';
import '../../../domain/repositories/analytics/analytics_category.dart';
import '../../../domain/repositories/analytics/analytics_dashboard.dart';
import '../../../domain/repositories/analytics/analytics_math.dart';
import '../../../domain/repositories/analytics/analytics_tags.dart';
import '../../../domain/repositories/budget_repository.dart';

/// Analytics section data, keyed by the section's inputs (month/currency/window
/// /…). Moving the per-section `_load` off `build` and into a `FutureProvider
/// .family` (R1) means Riverpod caches each result by its arguments: a rebuild
/// with the same arguments — e.g. the ~60fps rebuilds while dragging the
/// section FAB — is a cache hit, not a fresh query. Only a real input change
/// (month swipe, drill, window switch) runs a query, exactly once.
///
/// These are *not* autoDispose: the Analytics screen stays mounted across tabs
/// (IndexedStack), so leaving/returning would not re-run them. Freshness after
/// a mutation on another tab is handled by [invalidateAnalyticsSections], which
/// the screen calls when the Analytics tab regains focus.

typedef MonthCurrency = ({DateTime month, String currency});
typedef CategoryArgs = ({DateTime month, String currency, String? parentId});
typedef WindowArgs = ({DateTime month, String currency, int window});
typedef EventArgs = ({String eventId, DateTime? startsAt, DateTime? endsAt, String currency});

/// Every section family provider, so the screen can drop cached results in one
/// call when the tab regains focus (data may have changed elsewhere).
void invalidateAnalyticsSections(WidgetRef ref) {
  ref.invalidate(categorySectionProvider);
  ref.invalidate(tagSectionProvider);
  ref.invalidate(healthSectionProvider);
  ref.invalidate(burnUpProvider);
  ref.invalidate(trendSectionProvider);
  ref.invalidate(cashflowSectionProvider);
  ref.invalidate(paymentSectionProvider);
  ref.invalidate(behaviorSectionProvider);
  ref.invalidate(qualitySectionProvider);
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
    FutureProvider.family<CategorySectionData, CategoryArgs>((ref, a) async {
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
    FutureProvider.family<TagSectionData, MonthCurrency>((ref, a) async {
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

/// Health --------------------------------------------------------------------

final healthSectionProvider =
    FutureProvider.family<(FinancialHealth, String?), MonthCurrency>((ref, a) async {
  final health = await ref.watch(dashboardAnalyticsProvider).summary(a.month, a.currency);
  String? topLabel;
  if (health.topCategoryId != null) {
    final t = await ref.watch(translationsProvider.future);
    final cats = await ref.watch(referenceDataCacheProvider).categories();
    final matches = cats.where((c) => c.id == health.topCategoryId);
    if (matches.isNotEmpty) {
      topLabel = displayNameFor(t, name: matches.first.name, isDefault: matches.first.isDefault);
    }
  }
  return (health, topLabel);
});

final burnUpProvider =
    FutureProvider.family<({List<(int, int)> current, List<(int, int)> previous}), MonthCurrency>(
        (ref, a) => ref.watch(timeseriesAnalyticsProvider).burnUp(a.month, a.currency));

/// Trend ---------------------------------------------------------------------

class TrendSectionData {
  TrendSectionData(this.totals, this.movingAvg, this.mom, this.yoy, this.weekday, this.heat);
  final List<(DateTime, int)> totals;
  final List<(DateTime, double)> movingAvg;
  final double? mom;
  final double? yoy;
  final Map<int, double> weekday;
  final Map<int, int> heat;
}

final trendSectionProvider =
    FutureProvider.family<TrendSectionData, WindowArgs>((ref, a) async {
  final ts = ref.watch(timeseriesAnalyticsProvider);
  final range = DateRange.trailingMonths(a.month, a.window);
  final totals = await ts.monthlyTotals(range, a.currency);
  final movingAvg = await ts.movingAverage(range, a.currency);
  final mm = await ts.momYoY(a.month, a.currency);
  final weekday = await ts.averageByWeekday(range, a.currency);
  final heat = await ts.calendarHeat(a.month, a.currency);
  return TrendSectionData(totals, movingAvg, mm.mom.fraction, mm.yoy.fraction, weekday, heat);
});

/// Cash flow -----------------------------------------------------------------

class CashflowSectionData {
  CashflowSectionData(this.months, this.balance, this.savings);
  final List<MonthlyCashflow> months;
  final List<(DateTime, int)> balance;
  final List<(DateTime, int)> savings;
}

final cashflowSectionProvider =
    FutureProvider.family<CashflowSectionData, WindowArgs>((ref, a) async {
  final cf = ref.watch(cashflowAnalyticsProvider);
  final range = DateRange.trailingMonths(a.month, a.window);
  return CashflowSectionData(
    await cf.monthly(range, a.currency),
    await cf.cumulativeBalance(range, a.currency),
    await cf.cumulativeSavings(range, a.currency),
  );
});

/// Payment -------------------------------------------------------------------

class PaymentSectionData {
  PaymentSectionData(this.byMethod, this.labels);
  final Map<String?, int> byMethod;
  final Map<String, String> labels;
}

final paymentSectionProvider =
    FutureProvider.family<PaymentSectionData, MonthCurrency>((ref, a) async {
  final by = await ref.watch(paymentAnalyticsProvider).byMethod(DateRange.month(a.month), a.currency);
  final t = await ref.watch(translationsProvider.future);
  final methods = await ref.watch(referenceDataCacheProvider).paymentMethods();
  final labels = {for (final m in methods) m.id: displayNameFor(t, name: m.name, isDefault: m.isDefault)};
  return PaymentSectionData(by, labels);
});

/// Behavior ------------------------------------------------------------------

class BehaviorSectionData {
  BehaviorSectionData(this.stats, this.histogram, this.ant, this.refundRatio);
  final TicketStats stats;
  final List<int> histogram;
  final ({int total, int count}) ant;
  final double refundRatio;
}

final behaviorSectionProvider =
    FutureProvider.family<BehaviorSectionData, MonthCurrency>((ref, a) async {
  final b = ref.watch(behaviorAnalyticsProvider);
  final range = DateRange.month(a.month);
  final stats = await b.ticketStats(range, a.currency);
  final histogram = await b.histogram(range, a.currency, const [500, 1000, 2500, 5000, 10000]);
  final ant = await b.antSpend(range, a.currency, 500);
  final refunds = await b.refunds(range, a.currency);
  return BehaviorSectionData(stats, histogram, ant, refunds.ratio);
});

/// Quality -------------------------------------------------------------------

final qualitySectionProvider =
    FutureProvider.family<double, MonthCurrency>((ref, a) =>
        ref.watch(tagAnalyticsProvider).coverageGap(DateRange.month(a.month), a.currency));

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
    FutureProvider.family<List<BudgetRowData>, MonthCurrency>((ref, a) async {
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
  EventSectionData(this.total, this.perDay, this.timeline, this.outOfRange);
  final int total;
  final double? perDay;
  final List<(DateTime, int)> timeline;
  final int outOfRange;
}

final eventSectionProvider =
    FutureProvider.family<EventSectionData, EventArgs>((ref, a) async {
  final ev = ref.watch(eventAnalyticsProvider);
  final total = await ev.totalCost(eventId: a.eventId);
  final perDay = await ev.costPerDay(startsAt: a.startsAt, endsAt: a.endsAt, eventId: a.eventId);
  final timeline = await ev.timeline(eventId: a.eventId);
  final oor = await ev.outOfRange(eventId: a.eventId, startsAt: a.startsAt, endsAt: a.endsAt);
  return EventSectionData(total, perDay, timeline, oor.length);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/backup/backup_service.dart';
import '../../domain/repositories/analytics/analytics_behavior.dart';
import '../../domain/repositories/analytics/analytics_budgets.dart';
import '../../domain/repositories/analytics/analytics_cashflow.dart';
import '../../domain/repositories/analytics/analytics_category.dart';
import '../../domain/repositories/analytics/analytics_dashboard.dart';
import '../../domain/repositories/analytics/analytics_events.dart';
import '../../domain/repositories/analytics/analytics_payment.dart';
import '../../domain/repositories/analytics/analytics_tags.dart';
import '../../domain/repositories/analytics/analytics_timeseries.dart';
import '../../domain/repositories/budget_repository.dart';
import '../../domain/repositories/category_repository.dart';
import '../../domain/repositories/event_project_repository.dart';
import '../../domain/repositories/expense_repository.dart';
import '../../domain/repositories/payment_method_repository.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/repositories/recurring_repository.dart';
import '../../domain/repositories/reference_data_cache.dart';
import '../../domain/repositories/savings_goal_repository.dart';
import '../../domain/repositories/tag_repository.dart';
import '../i18n/display_name.dart';
import '../format/date.dart';
import '../i18n/translations.dart';
import 'keep_alive.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(databaseProvider)),
);

final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepository(ref.watch(databaseProvider)),
);

final tagGroupRepositoryProvider = Provider<TagGroupRepository>(
  (ref) => TagGroupRepository(ref.watch(databaseProvider)),
);

final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>(
  (ref) => PaymentMethodRepository(ref.watch(databaseProvider)),
);

final eventRepositoryProvider = Provider<EventRepository>(
  (ref) => EventRepository(ref.watch(databaseProvider)),
);

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => ProjectRepository(ref.watch(databaseProvider)),
);

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(databaseProvider)),
);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(ref.watch(databaseProvider), ref.watch(categoryRepositoryProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(databaseProvider)),
);

final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => RecurringRepository(ref.watch(databaseProvider)),
);

final savingsGoalRepositoryProvider = Provider<SavingsGoalRepository>(
  (ref) => SavingsGoalRepository(
    ref.watch(databaseProvider),
    ref.watch(categoryRepositoryProvider),
  ),
);

/// Live count of pending recurring occurrences — drives the Dashboard banner
/// and the Recurring screen badge, and refreshes as they're confirmed/skipped.
final pendingRecurringCountProvider = StreamProvider<int>(
  (ref) => ref.watch(recurringRepositoryProvider).watchPendingCount(),
);

/// Live list of pending recurring occurrences (the inbox on the Recurring
/// screen), ordered by due date.
final pendingRecurringProvider = StreamProvider<List<RecurringOccurrence>>(
  (ref) => ref.watch(recurringRepositoryProvider).watchPending(),
);

final backupServiceProvider = Provider<BackupService>((ref) => BackupService());

/// Index of the currently selected bottom-nav branch — the shell's
/// IndexedStack keeps every branch's State alive across tab switches, so
/// screens that need to refresh on becoming visible again (e.g. Analytics
/// after an expense was added on another tab) watch this instead of relying
/// on initState.
final currentTabIndexProvider = StateProvider<int>((ref) => 0);

// Analytics v2 engine (section-scoped calculators). Each is a thin Provider over
// the DB (+ CategoryRepository where the tree is needed), mirroring the other
// repository providers.
final categoryAnalyticsProvider = Provider<CategoryAnalytics>(
  (ref) => CategoryAnalytics(ref.watch(databaseProvider), ref.watch(categoryRepositoryProvider)),
);
final cashflowAnalyticsProvider = Provider<CashflowAnalytics>(
  (ref) => CashflowAnalytics(ref.watch(databaseProvider)),
);
final timeseriesAnalyticsProvider = Provider<TimeseriesAnalytics>(
  (ref) => TimeseriesAnalytics(ref.watch(databaseProvider)),
);
final behaviorAnalyticsProvider = Provider<BehaviorAnalytics>(
  (ref) => BehaviorAnalytics(ref.watch(databaseProvider)),
);
final paymentAnalyticsProvider = Provider<PaymentAnalytics>(
  (ref) => PaymentAnalytics(ref.watch(databaseProvider)),
);
final tagAnalyticsProvider = Provider<TagAnalytics>(
  (ref) => TagAnalytics(ref.watch(databaseProvider)),
);
final eventAnalyticsProvider = Provider<EventAnalytics>(
  (ref) => EventAnalytics(ref.watch(databaseProvider)),
);
final budgetAnalyticsProvider = Provider<BudgetAnalytics>(
  (ref) => BudgetAnalytics(ref.watch(budgetRepositoryProvider)),
);
final dashboardAnalyticsProvider = Provider<DashboardAnalytics>(
  (ref) => DashboardAnalytics(
    ref.watch(databaseProvider),
    ref.watch(categoryAnalyticsProvider),
    ref.watch(budgetAnalyticsProvider),
    ref.watch(budgetRepositoryProvider),
  ),
);

/// Every budget plus its spent figure for a month, live (BL-063): computed in
/// one batched pass and recomputed whenever budgets, transactions, tags or
/// categories change. Shared by the dashboard, the Budgets screen and
/// Analytics. Key it by the first day of the month (`DateTime(year, month)`).
final budgetProgressProvider =
    StreamProvider.autoDispose.family<BudgetMonthProgress, DateTime>((ref, month) {
  keepAliveFor(ref);
  return ref.watch(budgetRepositoryProvider).watchMonthProgress(month);
});

final referenceDataCacheProvider = Provider<ReferenceDataCache>((ref) {
  return ReferenceDataCache(
    categories: ref.watch(categoryRepositoryProvider),
    tags: ref.watch(tagRepositoryProvider),
    tagGroups: ref.watch(tagGroupRepositoryProvider),
    paymentMethods: ref.watch(paymentMethodRepositoryProvider),
    events: ref.watch(eventRepositoryProvider),
    projects: ref.watch(projectRepositoryProvider),
  );
});

/// Cached category list, backed by [ReferenceDataCache]. Widgets should watch
/// this instead of calling `referenceDataCacheProvider.categories()` inline in
/// `build`, which recreates the future (and re-triggers `FutureBuilder`'s
/// waiting state) on every rebuild. Invalidate alongside
/// `referenceDataCache.invalidate()` whenever categories are mutated.
final categoriesListProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(referenceDataCacheProvider).categories(),
);

/// Category id → translated display name, rebuilt only when the category list
/// or the language changes. List rows look labels up here in O(1) instead of
/// scanning the category list and translating per row on every build (BL-060).
final categoryLabelsProvider = Provider<Map<String, String>>((ref) {
  final categories = ref.watch(categoriesListProvider).valueOrNull;
  final translations = ref.watch(translationsProvider).valueOrNull;
  if (categories == null || translations == null) return const {};
  return {
    for (final c in categories) c.id: displayNameFor(translations, name: c.name, isDefault: c.isDefault),
  };
});

/// Live profile row (language/currency/theme) — the single source of truth
/// for app-wide settings, replacing Zustand's profile store.
final profileStreamProvider = StreamProvider<ProfileData>((ref) {
  return ref.watch(profileRepositoryProvider).watch();
});

/// Reloaded whenever the profile's language changes. Also loads that
/// language's date symbols, so once it resolves dates can be formatted in its
/// locale (see `ensureDateLocale`).
final translationsProvider = FutureProvider<Translations>((ref) async {
  final profile = await ref.watch(profileStreamProvider.future);
  final (translations, _) = await (Translations.load(profile.language), ensureDateLocale(profile.language)).wait;
  return translations;
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/backup/backup_service.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../../domain/repositories/budget_repository.dart';
import '../../domain/repositories/category_repository.dart';
import '../../domain/repositories/event_project_repository.dart';
import '../../domain/repositories/expense_repository.dart';
import '../../domain/repositories/payment_method_repository.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/repositories/reference_data_cache.dart';
import '../../domain/repositories/tag_repository.dart';
import '../i18n/translations.dart';

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

final backupServiceProvider = Provider<BackupService>((ref) => BackupService());

/// Index of the currently selected bottom-nav branch — the shell's
/// IndexedStack keeps every branch's State alive across tab switches, so
/// screens that need to refresh on becoming visible again (e.g. Analytics
/// after an expense was added on another tab) watch this instead of relying
/// on initState.
final currentTabIndexProvider = StateProvider<int>((ref) => 0);

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => AnalyticsRepository(ref.watch(databaseProvider), ref.watch(categoryRepositoryProvider)),
);

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

/// Live profile row (language/currency/theme) — the single source of truth
/// for app-wide settings, replacing Zustand's profile store.
final profileStreamProvider = StreamProvider<ProfileData>((ref) {
  return ref.watch(profileRepositoryProvider).watch();
});

/// Reloaded whenever the profile's language changes.
final translationsProvider = FutureProvider<Translations>((ref) async {
  final profile = await ref.watch(profileStreamProvider.future);
  return Translations.load(profile.language);
});

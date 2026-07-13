import 'package:drift/drift.dart';

import '../../data/database.dart';

const supportedLanguages = ['en', 'es', 'ca', 'fr', 'it'];

class ProfileRepository {
  ProfileRepository(this._db);

  final AppDatabase _db;

  Stream<ProfileData> watch() {
    return (_db.select(_db.profile)..where((p) => p.id.equals(1))).watchSingle();
  }

  Future<ProfileData> get() {
    return (_db.select(_db.profile)..where((p) => p.id.equals(1))).getSingle();
  }

  Future<void> setLanguage(String language) async {
    assert(supportedLanguages.contains(language));
    await (_db.update(_db.profile)..where((p) => p.id.equals(1))).write(
      ProfileCompanion(language: Value(language), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> setTheme(String theme) async {
    assert(theme == 'light' || theme == 'dark' || theme == 'system');
    await (_db.update(_db.profile)..where((p) => p.id.equals(1))).write(
      ProfileCompanion(theme: Value(theme), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> setHapticsEnabled(bool enabled) async {
    await (_db.update(_db.profile)..where((p) => p.id.equals(1))).write(
      ProfileCompanion(hapticsEnabled: Value(enabled), updatedAt: Value(DateTime.now())),
    );
  }

  /// v1 only supports EUR; kept as a real write path (not a no-op) so the
  /// latent multi-currency "warns, doesn't block" behavior has somewhere to
  /// live once more currencies are added (plan §3.8, §6).
  Future<void> setCurrency(String currency) async {
    await (_db.update(_db.profile)..where((p) => p.id.equals(1))).write(
      ProfileCompanion(currency: Value(currency), updatedAt: Value(DateTime.now())),
    );
  }
}

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/backup/backup_service.dart';

/// Guards the schema baseline (docs/database_baseline.md).
///
/// v9 is the oldest schema any install carries, so onUpgrade has no steps for
/// earlier versions. A pre-baseline file must be refused — never silently
/// migrated half-way or wiped — and the pre-migration auto-backup must still
/// be taken first.
void main() {
  late Directory tempDir;
  late BackupService service;

  String dbPath() => p.join(tempDir.path, 'despeses.sqlite');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('despeses_migration_test');
    service = BackupService(documentsDirProvider: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Rebuilds `profile` without the v10 column (BL-024), keeping its row, so
  /// the file really has the v9 shape. SQLite can't DROP a column that holds a
  /// foreign key, hence the table rebuild.
  Future<void> stripProfileToV9(AppDatabase db) async {
    final createSql = (await db
            .customSelect("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'profile'")
            .getSingle())
        .read<String>('sql');
    final v9Sql = createSql.replaceFirst(
        RegExp(r',\s*"favorite_payment_method_id" TEXT REFERENCES payment_methods\(id\) ON DELETE SET NULL'), '');
    expect(v9Sql, isNot(contains('favorite_payment_method_id')));
    const v9Columns = 'id, language, currency, theme, haptics_enabled, haptics_strength, created_at, updated_at';
    await db.customStatement('ALTER TABLE profile RENAME TO profile_v10');
    await db.customStatement(v9Sql);
    await db.customStatement('INSERT INTO profile ($v9Columns) SELECT $v9Columns FROM profile_v10');
    await db.customStatement('DROP TABLE profile_v10');
  }

  /// Creates a current-schema database with one expense, then stamps it with
  /// [version] (reshaping tables added to after it) so the next open goes
  /// through onUpgrade from there.
  Future<void> writeDatabaseAt(int version) async {
    final db = AppDatabase(NativeDatabase(File(dbPath())), service);
    final leaf = (await db.select(db.categories).get()).firstWhere((c) => c.type == 'expense');
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: 'e1',
          amount: 1250,
          currency: 'EUR',
          type: 'expense',
          date: DateTime(2026, 7, 1),
          categoryId: Value(leaf.id),
        ));
    if (version < 10) await stripProfileToV9(db);
    await db.customStatement('PRAGMA user_version = $version');
    await db.close();
  }

  test('the baseline matches the current schema version', () {
    final db = AppDatabase(NativeDatabase.memory(), service);
    addTearDown(db.close);
    expect(AppDatabase.baselineSchemaVersion, lessThanOrEqualTo(db.schemaVersion));
  });

  test('a database at the baseline opens with its data intact', () async {
    await writeDatabaseAt(AppDatabase.baselineSchemaVersion);

    final db = AppDatabase(NativeDatabase(File(dbPath())), service);
    addTearDown(db.close);

    expect((await db.select(db.expenses).getSingle()).amount, 1250);
    expect(await db.select(db.recurrings).get(), isEmpty);
    expect(await db.select(db.savingsGoals).get(), isEmpty);
  });

  test('v9 → v10 adds profile.favorite_payment_method_id (null, FK set null on delete)', () async {
    await writeDatabaseAt(9);

    final db = AppDatabase(NativeDatabase(File(dbPath())), service);
    addTearDown(db.close);

    final profile = await db.select(db.profile).getSingle();
    expect(profile.favoritePaymentMethodId, isNull);
    expect((await db.select(db.expenses).getSingle()).amount, 1250);

    final method = (await db.select(db.paymentMethods).get()).first;
    await db.update(db.profile).write(ProfileCompanion(favoritePaymentMethodId: Value(method.id)));
    expect((await db.select(db.profile).getSingle()).favoritePaymentMethodId, method.id);

    await (db.delete(db.paymentMethods)..where((m) => m.id.equals(method.id))).go();
    expect((await db.select(db.profile).getSingle()).favoritePaymentMethodId, isNull);
  });

  test('a pre-baseline database is refused, backed up and left untouched', () async {
    await writeDatabaseAt(AppDatabase.baselineSchemaVersion - 1);

    final db = AppDatabase(NativeDatabase(File(dbPath())), service);
    await expectLater(db.select(db.profile).get(), throwsA(isA<UnsupportedError>()));
    await db.close();

    final backups = await service.listBackups();
    expect(backups, isNotEmpty, reason: 'no pre-migration snapshot was taken');
    expect(backups.first.path, contains('pre_migration'));

    // The live file keeps its old version and data — nothing was wiped. Read it
    // raw: opening it through AppDatabase would rerun the refused migration.
    final raw = sqlite3.open(dbPath());
    addTearDown(raw.dispose);
    expect(raw.select('PRAGMA user_version').first.values.first,
        AppDatabase.baselineSchemaVersion - 1);
    expect(raw.select('SELECT amount FROM expenses').first['amount'], 1250);
  });
}

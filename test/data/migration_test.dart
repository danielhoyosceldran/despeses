import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/backup/backup_service.dart';

/// Regression test for the pre-v7 upgrade path.
///
/// Schemas older than v7 predate data-preserving migrations and are missing
/// columns the current queries SELECT (`categories.type`,
/// `profile.haptics_enabled`, `profile.haptics_strength`) while carrying ones
/// that are gone (`budgets.months`). `onUpgrade` used to fall through its
/// additive `if (from < N)` steps for those versions, leaving a database that
/// crashed every query with "no such column". It must rebuild instead — after
/// snapshotting the old file, so nothing is destroyed unrecoverably.
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

  /// Writes a database file shaped like schema v5: `categories` without the
  /// `type` column, `profile` without the haptics columns, and `budgets` with
  /// the long-removed `months` column.
  Future<void> writeV5Database() async {
    final legacy = NativeDatabase(File(dbPath()));
    final raw = AppDatabase(legacy);
    // Build the old shape by hand rather than through the generated schema,
    // which only knows the current one.
    await raw.customStatement('DROP TABLE IF EXISTS categories');
    await raw.customStatement('DROP TABLE IF EXISTS profile');
    await raw.customStatement('DROP TABLE IF EXISTS budgets');
    await raw.customStatement(
        'CREATE TABLE categories (id TEXT NOT NULL PRIMARY KEY, parent_id TEXT, '
        'name TEXT NOT NULL, is_default INTEGER NOT NULL DEFAULT 0)');
    await raw.customStatement(
        'CREATE TABLE profile (id INTEGER NOT NULL PRIMARY KEY DEFAULT 1, '
        "language TEXT NOT NULL DEFAULT 'en', currency TEXT NOT NULL DEFAULT 'EUR')");
    await raw.customStatement(
        'CREATE TABLE budgets (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, '
        'amount INTEGER NOT NULL, months TEXT)');
    await raw.customStatement("INSERT INTO categories (id, name) VALUES ('c1', 'Old category')");
    await raw.customStatement('INSERT INTO profile (id) VALUES (1)');
    await raw.customStatement('PRAGMA user_version = 5');
    await raw.close();
  }

  test('upgrading from a pre-v7 schema rebuilds a fully usable database', () async {
    await writeV5Database();

    final db = AppDatabase(NativeDatabase(File(dbPath())), service);
    addTearDown(db.close);

    // Every table the app queries must exist with its current columns — this is
    // what used to throw "no such column: haptics_strength".
    final profile = await db.select(db.profile).getSingle();
    expect(profile.currency, 'EUR');
    expect(profile.hapticsEnabled, isTrue);
    expect(profile.hapticsStrength, 1);

    // The rebuild reseeds, so the legacy row is gone and the current typed
    // forest is present.
    final categories = await db.select(db.categories).get();
    expect(categories.any((c) => c.name == 'Old category'), isFalse);
    expect(categories.where((c) => c.type == 'ahorro'), isNotEmpty);
    expect(categories.length, 51);

    // Tables added in v8/v9 are queryable too.
    expect(await db.select(db.recurrings).get(), isEmpty);
    expect(await db.select(db.savingsGoals).get(), isEmpty);

    // And the database accepts writes against the current schema.
    final leaf = categories.firstWhere((c) => c.type == 'expense');
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: 'e1',
          amount: 1250,
          currency: 'EUR',
          type: 'expense',
          date: DateTime(2026, 7, 1),
          categoryId: Value(leaf.id),
        ));
    expect((await db.select(db.expenses).getSingle()).amount, 1250);
  });

  test('the destructive pre-v7 rebuild is preceded by an auto-backup', () async {
    await writeV5Database();

    final db = AppDatabase(NativeDatabase(File(dbPath())), service);
    addTearDown(db.close);
    // Force the migration to run.
    await db.select(db.profile).getSingle();

    final backups = await service.listBackups();
    expect(backups, isNotEmpty, reason: 'no pre-migration snapshot was taken');
    expect(backups.first.path, contains('pre_migration'));
    // The snapshot must still hold the old data the rebuild dropped. Read it
    // with a raw sqlite3 connection: opening it through AppDatabase would run
    // the very migration under test against the snapshot and reseed it.
    final snapshot = sqlite3.open(backups.first.path);
    addTearDown(snapshot.dispose);
    expect(snapshot.select('PRAGMA user_version').first.values.first, 5);
    final oldRows =
        snapshot.select('SELECT name FROM categories').map((r) => r['name'] as String);
    expect(oldRows, contains('Old category'));
  });
}

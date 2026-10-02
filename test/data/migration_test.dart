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

  /// Creates a current-schema database with one expense, then stamps it with
  /// [version] so the next open goes through onUpgrade from there.
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

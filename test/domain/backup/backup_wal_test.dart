import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/backup/backup_service.dart';

/// Integration test for the WAL-safe backup/restore path (audit §B): a backup
/// taken with a checkpoint must capture transactions still living in the WAL,
/// and restoring it (deleting stale sidecars) must reproduce exactly that state.
void main() {
  late Directory tempDir;
  late BackupService service;
  late AppDatabase db;

  String dbPath() => p.join(tempDir.path, 'despeses.sqlite');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('despeses_wal_test');
    service = BackupService(documentsDirProvider: () async => tempDir);
    db = AppDatabase(NativeDatabase(File(dbPath())));
    await db.customStatement('PRAGMA journal_mode=WAL');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('checkpointed backup captures WAL-resident writes; restore reproduces them', () async {
    final cat = (await db.select(db.categories).get()).first;
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: 'e1',
          amount: 4200,
          currency: 'EUR',
          type: 'expense',
          date: DateTime(2026, 7, 1),
          categoryId: Value(cat.id),
        ));

    final backup = await service.createBackup(
      checkpoint: () => db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)'),
    );

    // Mutate after the backup, then tear the connection down.
    await (db.delete(db.expenses)..where((e) => e.id.equals('e1'))).go();
    await db.close();

    await service.restoreBackup(backup);

    // Reopen the restored file (sidecars were deleted by restore).
    db = AppDatabase(NativeDatabase(File(dbPath())));
    final rows = await db.select(db.expenses).get();
    expect(rows.map((e) => e.id), contains('e1'));
    expect(rows.firstWhere((e) => e.id == 'e1').amount, 4200);
  });
}

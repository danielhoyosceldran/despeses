import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/backup/backup_service.dart';

/// Writes a minimal database that passes [BackupService.validateBackup]: every
/// app table with the columns of schema [version] (no constraints, no rows),
/// [version] as user_version, and a `marker` table holding [marker] so tests
/// can tell copies apart. [extraColumns]/[dropColumns] (`table.column`) bend
/// the column set.
void writeDb(
  String path,
  String marker, {
  int version = AppDatabase.currentSchemaVersion,
  bool allTables = true,
  List<String> extraColumns = const [],
  List<String> dropColumns = const [],
}) {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
  final db = sqlite3.open(path);
  try {
    if (allTables) {
      final schemaVersion = version.clamp(AppDatabase.baselineSchemaVersion, AppDatabase.currentSchemaVersion);
      final schema = AppDatabase.schemaColumnsAt(schemaVersion);
      for (final c in extraColumns) {
        final [table, column] = c.split('.');
        schema[table]!.add(column);
      }
      for (final c in dropColumns) {
        final [table, column] = c.split('.');
        schema[table]!.remove(column);
      }
      for (final MapEntry(key: table, value: columns) in schema.entries) {
        db.execute('CREATE TABLE $table (${columns.map((c) => '"$c"').join(', ')})');
      }
    }
    db.execute('CREATE TABLE marker (v TEXT)');
    db.execute('INSERT INTO marker VALUES (?)', [marker]);
    db.userVersion = version;
  } finally {
    db.dispose();
  }
}

int readUserVersion(String path) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    return db.userVersion;
  } finally {
    db.dispose();
  }
}

String readMarker(String path) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    return db.select('SELECT v FROM marker').first.columnAt(0) as String;
  } finally {
    db.dispose();
  }
}

void main() {
  late Directory tempDir;
  late BackupService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('despeses_backup_test');
    service = BackupService(documentsDirProvider: () async => tempDir);
    // Simulate a live database file at the expected location.
    writeDb(p.join(tempDir.path, 'despeses.sqlite'), 'original-db-contents');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('createBackup copies the live db into a timestamped file under backups/', () async {
    final backup = await service.createBackup();

    expect(await backup.exists(), isTrue);
    expect(p.dirname(backup.path), p.join(tempDir.path, 'backups'));
    expect(readMarker(backup.path), 'original-db-contents');
  });

  test('listBackups returns newest first', () async {
    await service.createBackup();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.createBackup();

    final backups = await service.listBackups();
    expect(backups.length, 2);
    // Newest filename (later ISO timestamp) sorts first.
    expect(backups.first.path.compareTo(backups.last.path) > 0, isTrue);
  });

  test('restoreBackup overwrites the live db file with the backup contents', () async {
    final backup = await service.createBackup();
    final dbFile = File(p.join(tempDir.path, 'despeses.sqlite'));
    writeDb(dbFile.path, 'changed-after-backup');

    await service.restoreBackup(backup);

    expect(readMarker(dbFile.path), 'original-db-contents');
  });

  test('createBackup throws if there is no database file yet', () async {
    await File(p.join(tempDir.path, 'despeses.sqlite')).delete();
    expect(() => service.createBackup(), throwsStateError);
  });

  test('createBackup runs the checkpoint before copying', () async {
    var called = false;
    final backup = await service.createBackup(checkpoint: () async {
      called = true;
      // Mutate the live file inside the checkpoint; the copy must capture this,
      // proving the checkpoint ran first.
      writeDb(p.join(tempDir.path, 'despeses.sqlite'), 'after-checkpoint');
    });
    expect(called, isTrue);
    expect(readMarker(backup.path), 'after-checkpoint');
  });

  test('restoreBackup deletes stale -wal and -shm sidecars', () async {
    final backup = await service.createBackup();
    final dbPath = p.join(tempDir.path, 'despeses.sqlite');
    await File('$dbPath-wal').writeAsString('stale-wal');
    await File('$dbPath-shm').writeAsString('stale-shm');

    await service.restoreBackup(backup);

    expect(await File('$dbPath-wal').exists(), isFalse);
    expect(await File('$dbPath-shm').exists(), isFalse);
    expect(readMarker(dbPath), 'original-db-contents');
  });

  test('createAutoBackup copies main file plus WAL sidecars, never throwing', () async {
    final dbPath = p.join(tempDir.path, 'despeses.sqlite');
    await File('$dbPath-wal').writeAsString('wal-contents');
    await File('$dbPath-shm').writeAsString('shm-contents');

    final auto = await service.createAutoBackup();

    expect(auto, isNotNull);
    // Byte comparison: opening the copy would read the fake sidecars.
    expect(await auto!.readAsBytes(), await File(dbPath).readAsBytes());
    expect(await File('${auto.path}-wal').readAsString(), 'wal-contents');
    expect(await File('${auto.path}-shm').readAsString(), 'shm-contents');
  });

  test('createAutoBackup returns null when there is no database yet', () async {
    await File(p.join(tempDir.path, 'despeses.sqlite')).delete();
    expect(await service.createAutoBackup(), isNull);
  });

  test('restoreBackup first saves the current data as a pre_restore backup', () async {
    final backup = await service.createBackup();
    final dbFile = File(p.join(tempDir.path, 'despeses.sqlite'));
    writeDb(dbFile.path, 'current-data');
    expect(await service.latestPreRestoreBackup(), isNull);

    await service.restoreBackup(backup);

    final snapshot = await service.latestPreRestoreBackup();
    expect(snapshot, isNotNull);
    expect(p.basename(snapshot!.path), startsWith('despeses_pre_restore_'));
    expect(readMarker(snapshot.path), 'current-data');
    expect(readMarker(dbFile.path), 'original-db-contents');
  });

  test('restoring the pre_restore backup undoes the restore', () async {
    final backup = await service.createBackup();
    final dbFile = File(p.join(tempDir.path, 'despeses.sqlite'));
    writeDb(dbFile.path, 'current-data');
    await service.restoreBackup(backup);

    await service.restoreBackup((await service.latestPreRestoreBackup())!);

    expect(readMarker(dbFile.path), 'current-data');
  });

  test('takenAt parses the timestamp in a backup file name', () {
    expect(
      BackupService.takenAt(File('despeses_pre_restore_2026-10-02T13-37-58-123456.sqlite')),
      DateTime(2026, 10, 2, 13, 37, 58),
    );
    expect(BackupService.takenAt(File('whatever.sqlite')), isNull);
  });

  group('validateBackup', () {
    Future<void> expectRejected(String path, InvalidBackupReason reason) async {
      final dbPath = p.join(tempDir.path, 'despeses.sqlite');
      await expectLater(
        service.restoreBackup(File(path)),
        throwsA(isA<InvalidBackupException>().having((e) => e.reason, 'reason', reason)),
      );
      // Nothing was replaced and no pre_restore copy was made.
      expect(readMarker(dbPath), 'original-db-contents');
      expect(await service.latestPreRestoreBackup(), isNull);
    }

    test('accepts a valid backup', () {
      final path = p.join(tempDir.path, 'ok.sqlite');
      writeDb(path, 'ok');
      expect(() => service.validateBackup(File(path)), returnsNormally);
    });

    test('rejects a file that is not SQLite', () async {
      final path = p.join(tempDir.path, 'notes.sqlite');
      await File(path).writeAsString('just some text, definitely not a database');
      await expectRejected(path, InvalidBackupReason.notABackup);
    });

    test('rejects an SQLite file without the app tables', () async {
      final path = p.join(tempDir.path, 'other.sqlite');
      writeDb(path, 'other', allTables: false);
      await expectRejected(path, InvalidBackupReason.notABackup);
    });

    test('rejects a backup from a newer schema', () async {
      final path = p.join(tempDir.path, 'newer.sqlite');
      writeDb(path, 'newer', version: AppDatabase.currentSchemaVersion + 1);
      await expectRejected(path, InvalidBackupReason.tooNew);
    });

    test('rejects a backup older than the baseline', () async {
      final path = p.join(tempDir.path, 'older.sqlite');
      writeDb(path, 'older', version: AppDatabase.baselineSchemaVersion - 1);
      await expectRejected(path, InvalidBackupReason.tooOld);
    });

    test('rejects a backup with a column its schema version does not define, naming it', () async {
      final path = p.join(tempDir.path, 'extra.sqlite');
      writeDb(path, 'extra', extraColumns: ['expenses.mystery', 'tags.legacy']);
      await expectRejected(path, InvalidBackupReason.extraColumns);
      expect(
        () => service.validateBackup(File(path)),
        throwsA(isA<InvalidBackupException>()
            .having((e) => e.detail, 'detail', allOf(contains('expenses.mystery'), contains('tags.legacy')))),
      );
    });

    test('a column from a later version counts as extra', () async {
      final path = p.join(tempDir.path, 'v9_plus.sqlite');
      writeDb(path, 'v9+', version: 9, extraColumns: ['profile.favorite_payment_method_id']);
      await expectRejected(path, InvalidBackupReason.extraColumns);
    });

    test('rejects a backup missing a column no migration adds, naming it', () async {
      final path = p.join(tempDir.path, 'missing.sqlite');
      writeDb(path, 'missing', dropColumns: ['expenses.amount']);
      await expectRejected(path, InvalidBackupReason.missingColumns);
      expect(
        () => service.validateBackup(File(path)),
        throwsA(isA<InvalidBackupException>().having((e) => e.detail, 'detail', contains('expenses.amount'))),
      );
    });

    test('an older backup with the columns of its own version needs no re-stamp', () async {
      final path = p.join(tempDir.path, 'v9.sqlite');
      writeDb(path, 'v9', version: 9);
      expect(service.validateBackup(File(path)), 9);

      await service.restoreBackup(File(path));
      expect(readUserVersion(p.join(tempDir.path, 'despeses.sqlite')), 9);
    });

    test('missing columns a migration adds: the restored copy is stamped to migrate them', () async {
      final path = p.join(tempDir.path, 'v10_short.sqlite');
      writeDb(path, 'v10-short', version: 10, dropColumns: ['profile.favorite_payment_method_id']);
      expect(service.validateBackup(File(path)), 9);

      await service.restoreBackup(File(path));

      final dbPath = p.join(tempDir.path, 'despeses.sqlite');
      expect(readMarker(dbPath), 'v10-short');
      expect(readUserVersion(dbPath), 9);
      expect(readUserVersion(path), 10, reason: 'the picked file itself must not be modified');
    });
  });
}

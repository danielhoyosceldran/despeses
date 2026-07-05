import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:despeses/domain/backup/backup_service.dart';

void main() {
  late Directory tempDir;
  late BackupService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('despeses_backup_test');
    service = BackupService(documentsDirProvider: () async => tempDir);
    // Simulate a live database file at the expected location.
    await File(p.join(tempDir.path, 'despeses.sqlite')).writeAsString('original-db-contents');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('createBackup copies the live db into a timestamped file under backups/', () async {
    final backup = await service.createBackup();

    expect(await backup.exists(), isTrue);
    expect(p.dirname(backup.path), p.join(tempDir.path, 'backups'));
    expect(await backup.readAsString(), 'original-db-contents');
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
    await dbFile.writeAsString('changed-after-backup');

    await service.restoreBackup(backup);

    expect(await dbFile.readAsString(), 'original-db-contents');
  });

  test('createBackup throws if there is no database file yet', () async {
    await File(p.join(tempDir.path, 'despeses.sqlite')).delete();
    expect(() => service.createBackup(), throwsStateError);
  });
}

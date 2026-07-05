import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _dbFileName = 'despeses.sqlite';
const _backupsFolderName = 'backups';

/// Local `.sqlite` file copy + share sheet (plan §5.4, v1 scope). The
/// interface is intentionally the shape a future periodic-backup scheduler
/// would need (`createBackup`/`restoreBackup`/`listBackups`), even though
/// only manual, on-demand backups are wired up in v1.
class BackupService {
  BackupService({Future<Directory> Function()? documentsDirProvider})
      : _documentsDirProvider = documentsDirProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirProvider;

  Future<String> _dbFilePath() async {
    final dir = await _documentsDirProvider();
    return p.join(dir.path, _dbFileName);
  }

  Future<Directory> _backupsDirectory() async {
    final dir = await _documentsDirProvider();
    final backupsDir = Directory(p.join(dir.path, _backupsFolderName));
    if (!await backupsDir.exists()) await backupsDir.create(recursive: true);
    return backupsDir;
  }

  /// Copies the live database to a timestamped file under the app's backups
  /// folder and returns it, ready to be shared (e.g. via `share_plus`).
  Future<File> createBackup() async {
    final dbPath = await _dbFilePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw StateError('No database file found at $dbPath');
    }
    final backupsDir = await _backupsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-');
    final backupPath = p.join(backupsDir.path, 'despeses_backup_$timestamp.sqlite');
    return dbFile.copy(backupPath);
  }

  /// Overwrites the live database with [backupFile]'s contents. The caller
  /// must close the active `AppDatabase` connection before calling this and
  /// reopen (or recreate the provider) after — restoring while the database
  /// is open would corrupt it.
  Future<void> restoreBackup(File backupFile) async {
    final dbPath = await _dbFilePath();
    await backupFile.copy(dbPath);
  }

  Future<List<File>> listBackups() async {
    final backupsDir = await _backupsDirectory();
    final entries = await backupsDir.list().toList();
    final files = entries.whereType<File>().where((f) => f.path.endsWith('.sqlite')).toList();
    files.sort((a, b) => b.path.compareTo(a.path)); // newest first (ISO timestamp in name)
    return files;
  }
}

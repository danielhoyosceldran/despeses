import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _dbFileName = 'despeses.sqlite';
const _backupsFolderName = 'backups';

/// WAL/shared-memory sidecar files SQLite keeps next to the main `.sqlite`.
const _sidecarSuffixes = ['-wal', '-shm'];

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

  String _timestamp() =>
      DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-');

  /// Copies the live database to a timestamped file under the app's backups
  /// folder and returns it, ready to be shared (e.g. via `share_plus`).
  ///
  /// [checkpoint] must flush the WAL into the main `.sqlite` file before the
  /// copy so the resulting single-file backup is complete (the `-wal`/`-shm`
  /// sidecars are intentionally not copied). Callers holding a live connection
  /// pass a `PRAGMA wal_checkpoint(TRUNCATE)` here; without it the last
  /// transactions still sitting in the WAL would be missing from the backup.
  Future<File> createBackup({Future<void> Function()? checkpoint}) async {
    final dbPath = await _dbFilePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw StateError('No database file found at $dbPath');
    }
    if (checkpoint != null) await checkpoint();
    final backupsDir = await _backupsDirectory();
    final backupPath = p.join(backupsDir.path, 'despeses_backup_${_timestamp()}.sqlite');
    return dbFile.copy(backupPath);
  }

  /// Best-effort safety copy taken automatically right before a schema
  /// migration mutates the database. It cannot checkpoint (the migration owns
  /// the open connection), so it copies the main file together with its
  /// `-wal`/`-shm` sidecars to preserve any not-yet-checkpointed transactions.
  /// Returns the main backup file, or null if there is no database yet or the
  /// copy failed — a failed safety copy must never block the app from opening.
  Future<File?> createAutoBackup({String label = 'pre_migration'}) async {
    try {
      final dbPath = await _dbFilePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return null;
      final backupsDir = await _backupsDirectory();
      final base = 'despeses_${label}_${_timestamp()}';
      final mainCopy = await dbFile.copy(p.join(backupsDir.path, '$base.sqlite'));
      for (final suffix in _sidecarSuffixes) {
        final sidecar = File('$dbPath$suffix');
        if (await sidecar.exists()) {
          await sidecar.copy(p.join(backupsDir.path, '$base.sqlite$suffix'));
        }
      }
      return mainCopy;
    } catch (_) {
      return null;
    }
  }

  /// Overwrites the live database with [backupFile]'s contents. The caller
  /// must close the active `AppDatabase` connection before calling this and
  /// reopen (or recreate the provider) after — restoring while the database
  /// is open would corrupt it.
  ///
  /// Also replaces the live `-wal`/`-shm` sidecars with the backup's own (if
  /// any) so that transactions not yet checkpointed into a `createAutoBackup`
  /// snapshot are not lost. Leaving a stale live sidecar behind instead would
  /// let SQLite replay old transactions on top of the restored file,
  /// corrupting or mixing state, so any sidecar without a backup counterpart
  /// is deleted rather than kept.
  Future<void> restoreBackup(File backupFile) async {
    final dbPath = await _dbFilePath();
    await backupFile.copy(dbPath);
    for (final suffix in _sidecarSuffixes) {
      final sidecar = File('$dbPath$suffix');
      final backupSidecar = File('${backupFile.path}$suffix');
      if (await backupSidecar.exists()) {
        await backupSidecar.copy('$dbPath$suffix');
      } else if (await sidecar.exists()) {
        await sidecar.delete();
      }
    }
  }

  Future<List<File>> listBackups() async {
    final backupsDir = await _backupsDirectory();
    final entries = await backupsDir.list().toList();
    final files = entries.whereType<File>().where((f) => f.path.endsWith('.sqlite')).toList();
    files.sort((a, b) => b.path.compareTo(a.path)); // newest first (ISO timestamp in name)
    return files;
  }
}

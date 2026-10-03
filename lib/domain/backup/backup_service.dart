import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../data/database.dart';

const _dbFileName = 'despeses.sqlite';
const _backupsFolderName = 'backups';

/// Why [BackupService.validateBackup] rejected a file.
enum InvalidBackupReason {
  /// Not an SQLite database, corrupt, or missing the app's tables.
  notABackup,

  /// Made by a newer app version (schema above [AppDatabase.currentSchemaVersion]).
  tooNew,

  /// Older than [AppDatabase.baselineSchemaVersion]; can't be migrated.
  tooOld,

  /// Has columns its schema version doesn't define (never produced by the
  /// app). [InvalidBackupException.detail] lists them as `table.column`.
  extraColumns,

  /// Lacks columns that no migration step can add (e.g. a baseline column).
  /// [InvalidBackupException.detail] lists them as `table.column`.
  missingColumns,
}

class InvalidBackupException implements Exception {
  const InvalidBackupException(this.reason, [this.detail]);

  final InvalidBackupReason reason;
  final String? detail;

  @override
  String toString() => 'InvalidBackupException(${reason.name}${detail == null ? '' : ': $detail'})';
}

/// Tables every baseline (v9+) database has; see docs/database_baseline.md and
/// lib/data/tables.dart.
const _requiredTables = {
  'profile',
  'tag_groups',
  'tags',
  'categories',
  'payment_methods',
  'events',
  'projects',
  'expenses',
  'expense_tags',
  'budgets',
  'recurrings',
  'recurring_tags',
  'recurring_occurrences',
  'savings_goals',
};

/// [BackupService.createAutoBackup] label of the safety copy taken right
/// before a restore overwrites the live database.
const preRestoreLabel = 'pre_restore';

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
  ///
  /// Before overwriting, the current data is saved as a [preRestoreLabel]
  /// auto-backup so a wrong pick can be undone (see [latestPreRestoreBackup]).
  /// If that safety copy fails while there is data to lose, the restore is
  /// aborted with a [StateError] and nothing is touched.
  ///
  /// The file is validated first ([validateBackup]); an invalid one throws an
  /// [InvalidBackupException] before anything is touched. If it lacks columns
  /// that a migration step adds, the restored copy (never the picked file) is
  /// stamped with the schema version its columns actually match, so the next
  /// open runs onUpgrade from there and adds them.
  Future<void> restoreBackup(File backupFile) async {
    final (:version, :migrateFrom) = _validate(backupFile);
    final dbPath = await _dbFilePath();
    if (await File(dbPath).exists()) {
      final snapshot = await createAutoBackup(label: preRestoreLabel);
      if (snapshot == null) {
        throw StateError('Could not save the current data before restoring; restore aborted.');
      }
    }
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
    if (migrateFrom != version) {
      final restored = sqlite3.open(dbPath);
      try {
        restored.userVersion = migrateFrom;
      } finally {
        restored.dispose();
      }
    }
  }

  /// Checks that [file] is a database this app can open before it replaces the
  /// live one: opened read-only, it must pass `PRAGMA integrity_check`, have
  /// all the app's tables, a `user_version` between
  /// [AppDatabase.baselineSchemaVersion] and [AppDatabase.currentSchemaVersion],
  /// and columns matching that version ([AppDatabase.schemaColumnsAt]).
  /// Throws an [InvalidBackupException] otherwise.
  ///
  /// Returns the schema version the file's columns actually match — its
  /// `user_version`, or a lower one when the only missing columns are exactly
  /// those that the migration steps above it add (`restoreBackup` migrates
  /// from there). An extra column, or a missing one no step adds, is rejected.
  int validateBackup(File file) => _validate(file).migrateFrom;

  ({int version, int migrateFrom}) _validate(File file) {
    final Database db;
    try {
      db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    } on SqliteException catch (e) {
      throw InvalidBackupException(InvalidBackupReason.notABackup, e.message);
    }
    try {
      final int version;
      final Set<String> tables;
      try {
        final integrity = db.select('PRAGMA integrity_check');
        if (integrity.length != 1 || integrity.first.columnAt(0) != 'ok') {
          throw const InvalidBackupException(InvalidBackupReason.notABackup, 'integrity_check failed');
        }
        tables = {
          for (final row in db.select("SELECT name FROM sqlite_master WHERE type = 'table'"))
            row['name'] as String,
        };
        version = db.userVersion;
      } on SqliteException catch (e) {
        // e.g. "file is not a database".
        throw InvalidBackupException(InvalidBackupReason.notABackup, e.message);
      }
      final missing = _requiredTables.difference(tables);
      if (missing.isNotEmpty) {
        throw InvalidBackupException(InvalidBackupReason.notABackup, 'missing tables: ${missing.join(', ')}');
      }
      if (version > AppDatabase.currentSchemaVersion) {
        throw InvalidBackupException(InvalidBackupReason.tooNew, 'schema v$version');
      }
      if (version < AppDatabase.baselineSchemaVersion) {
        throw InvalidBackupException(InvalidBackupReason.tooOld, 'schema v$version');
      }
      return (version: version, migrateFrom: _matchColumns(db, version));
    } finally {
      db.dispose();
    }
  }

  /// See [validateBackup]'s return value.
  int _matchColumns(Database db, int version) {
    final expected = AppDatabase.schemaColumnsAt(version);
    final actual = <String, Set<String>>{};
    try {
      for (final table in expected.keys) {
        actual[table] = {for (final row in db.select('PRAGMA table_info("$table")')) row['name'] as String};
      }
    } on SqliteException catch (e) {
      throw InvalidBackupException(InvalidBackupReason.notABackup, e.message);
    }

    final extra = [
      for (final table in expected.keys)
        for (final column in actual[table]!.difference(expected[table]!)) '$table.$column',
    ];
    if (extra.isNotEmpty) {
      throw InvalidBackupException(InvalidBackupReason.extraColumns, extra.join(', '));
    }

    // actual ⊆ expected now; find the newest version the columns match exactly.
    bool matches(Map<String, Set<String>> columns) =>
        columns.entries.every((e) => actual[e.key]!.length == e.value.length && actual[e.key]!.containsAll(e.value));
    for (var v = version; v >= AppDatabase.baselineSchemaVersion; v--) {
      if (matches(v == version ? expected : AppDatabase.schemaColumnsAt(v))) return v;
    }
    final missing = [
      for (final table in expected.keys)
        for (final column in expected[table]!.difference(actual[table]!)) '$table.$column',
    ];
    throw InvalidBackupException(InvalidBackupReason.missingColumns, missing.join(', '));
  }

  /// The most recent [preRestoreLabel] safety copy (the data as it was before
  /// the last restore), or null if no restore has been made yet.
  Future<File?> latestPreRestoreBackup() async {
    final backupsDir = await _backupsDirectory();
    final prefix = 'despeses_${preRestoreLabel}_';
    final files = (await backupsDir.list().toList())
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith(prefix) && f.path.endsWith('.sqlite'))
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.path.compareTo(a.path)); // newest first (ISO timestamp in name)
    return files.first;
  }

  /// When [backup] was taken, parsed from the timestamp in its file name (the
  /// file's mtime is unreliable: copies may keep the source's). Null if the
  /// name has no timestamp.
  static DateTime? takenAt(File backup) {
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})').firstMatch(p.basename(backup.path));
    if (m == null) return null;
    final v = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    return DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
  }

  Future<List<File>> listBackups() async {
    final backupsDir = await _backupsDirectory();
    final entries = await backupsDir.list().toList();
    final files = entries.whereType<File>().where((f) => f.path.endsWith('.sqlite')).toList();
    files.sort((a, b) => b.path.compareTo(a.path)); // newest first (ISO timestamp in name)
    return files;
  }
}

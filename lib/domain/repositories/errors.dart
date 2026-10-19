import 'package:sqlite3/sqlite3.dart';

/// Thrown when an insert/update violates a UNIQUE constraint (SQLite extended
/// result code 2067). Repos catch the raw [SqliteException] and rethrow this
/// so callers can show a localized message instead of a crashing on raw SQL text.
class DuplicateNameException implements Exception {
  const DuplicateNameException(this.name);

  final String name;
}

/// Thrown when deleting a payment method would leave none: a new transaction
/// requires one, so at least one must always exist (BL-024).
class LastPaymentMethodException implements Exception {
  const LastPaymentMethodException();
}

/// Runs [action] and converts a UNIQUE-constraint [SqliteException] into a
/// [DuplicateNameException]. Any other exception propagates unchanged.
Future<T> guardUniqueName<T>(String name, Future<T> Function() action) async {
  try {
    return await action();
  } on SqliteException catch (e) {
    if (e.extendedResultCode == 2067) {
      throw DuplicateNameException(name);
    }
    rethrow;
  }
}

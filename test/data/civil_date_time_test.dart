import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/data/civil_date_time.dart';
import 'package:despeses/data/database.dart';

/// BL-042: accounting dates are civil date/times, independent of the device's
/// time zone.
void main() {
  test('encodes the wall-clock components as UTC, whatever the zone', () {
    final value = DateTime(2026, 10, 3, 0, 30, 15);
    expect(CivilDateTimeType.encode(value), DateTime.utc(2026, 10, 3, 0, 30, 15).millisecondsSinceEpoch ~/ 1000);
  });

  test('decodes to a local DateTime with the same components', () {
    final decoded = CivilDateTimeType.decode(DateTime.utc(2026, 12, 31, 23, 45).millisecondsSinceEpoch ~/ 1000);
    expect(decoded.isUtc, isFalse);
    expect(decoded, DateTime(2026, 12, 31, 23, 45));
  });

  test('a UTC instant is taken at its local wall-clock time', () {
    final local = DateTime(2026, 7, 1, 12);
    expect(CivilDateTimeType.encode(local.toUtc()), CivilDateTimeType.encode(local));
  });

  test('expenses.date round-trips and range filters bind through the civil type', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final date = DateTime(2026, 10, 31, 23, 30);
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: 'e1',
          amount: 100,
          currency: 'EUR',
          type: 'expense',
          date: date,
        ));

    final raw = await db.customSelect('SELECT date FROM expenses').getSingle();
    expect(raw.read<int>('date'), DateTime.utc(2026, 10, 31, 23, 30).millisecondsSinceEpoch ~/ 1000);
    expect((await db.select(db.expenses).getSingle()).date, date);

    final inOctober = await (db.select(db.expenses)
          ..where((e) => e.date.isBiggerOrEqualValue(DateTime(2026, 10)))
          ..where((e) => e.date.isSmallerThanValue(DateTime(2026, 11))))
        .get();
    expect(inOctober, hasLength(1));

    final rawFilter = await db.customSelect('SELECT id FROM expenses WHERE date >= ?',
        variables: [civilVariable(DateTime(2026, 11))]).get();
    expect(rawFilter, isEmpty);
  });
}

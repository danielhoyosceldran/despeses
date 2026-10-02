import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/search/transaction_search.dart';

Expense _tx(int amount, {String? description, String? notes}) {
  final now = DateTime(2026, 3, 10);
  return Expense(
    id: 'x',
    amount: amount,
    currency: 'EUR',
    type: 'expense',
    date: now,
    description: description,
    notes: notes,
    createdAt: now,
    updatedAt: now,
  );
}

bool _match(String query, Expense e) => TransactionQuery.parse(query).matches(e);

void main() {
  test('parseAmountCents handles both decimal marks and thousands separators', () {
    expect(parseAmountCents('12'), 1200);
    expect(parseAmountCents('12,5'), 1250);
    expect(parseAmountCents('12.50'), 1250);
    expect(parseAmountCents('1.234,56'), 123456);
    expect(parseAmountCents('1,234.56'), 123456);
    expect(parseAmountCents('1.234'), 123400);
    expect(parseAmountCents('€30'), 3000);
    expect(parseAmountCents('abc'), isNull);
    expect(parseAmountCents(','), isNull);
  });

  test('text matches title or notes, case- and accent-insensitive, all terms required', () {
    final e = _tx(1000, description: 'Café amb Jordi', notes: 'Plaça Major');
    expect(_match('cafe', e), isTrue);
    expect(_match('PLACA', e), isTrue);
    expect(_match('cafe jordi', e), isTrue);
    expect(_match('cafe pere', e), isFalse);
  });

  test('amount operators', () {
    final e = _tx(2550);
    expect(_match('>25', e), isTrue);
    expect(_match('> 25', e), isTrue);
    expect(_match('<25', e), isFalse);
    expect(_match('>=25,5', e), isTrue);
    expect(_match('<=25.50', e), isTrue);
    expect(_match('=25,50', e), isTrue);
    expect(_match('!=25,50', e), isFalse);
    expect(_match('>20 <30', e), isTrue);
    expect(_match('>20 <25', e), isFalse);
  });

  test('bare number matches the exact amount or the text', () {
    expect(_match('25,50', _tx(2550)), isTrue);
    expect(_match('2026', _tx(100, description: 'Renda 2026')), isTrue);
    expect(_match('99', _tx(100, description: 'Renda')), isFalse);
  });

  test('combined text and amount', () {
    final e = _tx(4000, description: 'Mercadona');
    expect(_match('merca >30', e), isTrue);
    expect(_match('merca <30', e), isFalse);
  });

  test('empty query matches everything', () {
    expect(TransactionQuery.parse('   ').isEmpty, isTrue);
    expect(_match('', _tx(1)), isTrue);
  });
}

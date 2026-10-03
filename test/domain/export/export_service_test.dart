import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/core/i18n/translations.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/export/export_service.dart';

Category _category(String id, String name, {String? parentId, bool isDefault = false}) {
  return Category(
    id: id,
    type: 'expense',
    parentId: parentId,
    name: name,
    isDefault: isDefault,
    position: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

Expense _expense(
  String id, {
  required int amount,
  required String type,
  String? description,
  String? categoryId,
}) {
  return Expense(
    id: id,
    amount: amount,
    currency: 'EUR',
    type: type,
    date: DateTime(2026, 3, 15),
    description: description,
    categoryId: categoryId,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final translations = Translations({
    'expenses': {'type_expense': 'Expense', 'type_income': 'Income', 'type_refund': 'Refund', 'type_ahorro': 'Savings'},
    'category': {'food': 'Food'},
    'analytics': {'total_label': 'TOTAL'},
    'dashboard': {'net_balance': 'Net balance'},
    'export': {
      'col_date': 'Fecha',
      'col_type': 'Tipo',
      'col_amount': 'Importe',
      'col_currency': 'Moneda',
      'col_description': 'Título',
      'col_category': 'Categoría',
      'col_payment': 'Pago',
      'col_event': 'Evento',
      'col_project': 'Proyecto',
      'col_tags': 'Etiquetas',
    },
  });
  final header = buildExportHeader(translations);

  test('category path joins parent > child using displayName, respecting is_default', () async {
    final root = _category('root', 'category.food', isDefault: true);
    final child = _category('child', 'Custom sub', parentId: 'root');

    final rows = buildExportRows(
      expenses: [_expense('e1', amount: 1000, type: 'expense', categoryId: 'child')],
      categoriesById: {'root': root, 'child': child},
      paymentMethodsById: const {},
      eventsById: const {},
      projectsById: const {},
      tagIdsByExpenseId: const {},
      tagsById: const {},
      translations: translations,
    );

    expect(rows.single[5], 'Food > Custom sub');
  });

  test('every row has exactly 10 columns and amount formatted with 2 decimals', () {
    final rows = buildExportRows(
      expenses: [_expense('e1', amount: 1250, type: 'income', description: 'Salary')],
      categoriesById: const {},
      paymentMethodsById: const {},
      eventsById: const {},
      projectsById: const {},
      tagIdsByExpenseId: const {},
      tagsById: const {},
      translations: translations,
    );

    expect(rows.single.length, exportColumnCount);
    expect(rows.single[1], 'Income');
    expect(rows.single[2], '12.50');
    expect(rows.single[4], 'Salary');
  });

  test('CSV escapes commas/quotes/newlines and starts with a UTF-8 BOM', () {
    final csv = buildExportCsv([
      ['2026-03-15', 'Expense', '10.00', 'EUR', 'Coffee, "the good one"', '', '', '', '', ''],
    ], header: header);

    expect(csv.startsWith('﻿'), isTrue);
    expect(csv, contains('"Coffee, ""the good one"""'));
  });

  test('CSV header is translated', () {
    final csv = buildExportCsv(const [], header: header);
    expect(csv.substring(1).trim(), 'Fecha,Tipo,Importe,Moneda,Título,Categoría,Pago,Evento,Proyecto,Etiquetas');
  });

  test('semicolon format: ";" delimiter, decimal comma in amount only, ";" fields quoted', () {
    final csv = buildExportCsv([
      ['2026-03-15', 'Expense', '10.50', 'EUR', 'A; B. C', '', '', '', '', ''],
    ], header: header, format: CsvFormat.semicolon);

    final lines = csv.substring(1).trim().split(RegExp(r'\r?\n'));
    expect(lines.first, startsWith('Fecha;Tipo;Importe;'));
    expect(lines.last, '2026-03-15;Expense;10,50;EUR;"A; B. C";;;;;');
  });

  test('CsvFormat.forLocale: comma for en, semicolon for es/ca/fr/it', () {
    expect(CsvFormat.forLocale('en'), CsvFormat.comma);
    for (final locale in ['es', 'ca', 'fr', 'it']) {
      expect(CsvFormat.forLocale(locale), CsvFormat.semicolon);
    }
  });

  test('totals: one row per present type plus net balance (income − spent − savings)', () {
    final totals = buildExportTotals(
      expenses: [
        _expense('e1', amount: 3000, type: 'expense'),
        _expense('e2', amount: 1000, type: 'expense'),
        _expense('i1', amount: 10000, type: 'income'),
        _expense('r1', amount: 500, type: 'refund'),
        _expense('a1', amount: 2000, type: 'ahorro'),
      ],
      translations: translations,
    );

    expect(totals.map((r) => r.take(4).toList()).toList(), [
      ['TOTAL', 'Expense', '40.00', 'EUR'],
      ['TOTAL', 'Income', '100.00', 'EUR'],
      ['TOTAL', 'Refund', '5.00', 'EUR'],
      ['TOTAL', 'Savings', '20.00', 'EUR'],
      ['Net balance', '', '45.00', 'EUR'],
    ]);
    expect(totals.every((r) => r.length == exportColumnCount), isTrue);
  });

  test('totals skip absent types and are empty without transactions', () {
    final totals = buildExportTotals(
      expenses: [_expense('e1', amount: 1000, type: 'expense')],
      translations: translations,
    );
    expect(totals.map((r) => r[1]).toList(), ['Expense', '']);
    expect(totals.last[2], '-10.00');
    expect(buildExportTotals(expenses: const [], translations: translations), isEmpty);
  });

  test('buildExportPdf renders accented text without crashing (bundled Inter font, not Helvetica)', () async {
    final bytes = await buildExportPdf(
      [
        ['2026-03-15', 'Expense', '10.00', 'EUR', 'Café con leche - Ñoño', '', '', '', '', ''],
      ],
      rangeLabel: 'March 2026',
      header: header,
      title: 'Movimientos',
      totals: buildExportTotals(
        expenses: [_expense('e1', amount: 1000, type: 'expense')],
        translations: translations,
      ),
    );
    expect(bytes.isNotEmpty, isTrue);
  });
}

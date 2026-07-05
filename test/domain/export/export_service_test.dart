import 'package:flutter_test/flutter_test.dart';
import 'package:despeses/core/i18n/translations.dart';
import 'package:despeses/data/database.dart';
import 'package:despeses/domain/export/export_service.dart';

Category _category(String id, String name, {String? parentId, bool isDefault = false}) {
  return Category(
    id: id,
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
    'expenses': {'type_expense': 'Expense', 'type_income': 'Income', 'type_refund': 'Refund'},
    'category': {'food': 'Food'},
  });

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
    ]);

    expect(csv.startsWith('﻿'), isTrue);
    expect(csv, contains('"Coffee, ""the good one"""'));
  });

  test('buildExportPdf renders accented text without crashing (bundled Inter font, not Helvetica)', () async {
    final bytes = await buildExportPdf(
      [
        ['2026-03-15', 'Expense', '10.00', 'EUR', 'Café con leche - Ñoño', '', '', '', '', ''],
      ],
      rangeLabel: 'March 2026',
    );
    expect(bytes.isNotEmpty, isTrue);
  });
}

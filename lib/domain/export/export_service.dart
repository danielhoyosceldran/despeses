import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/i18n/display_name.dart';
import '../../core/i18n/translations.dart';
import '../../data/database.dart';

const exportColumnCount = 10;

/// Builds the 10-column export table (plan §9): date, translated type,
/// amount (2 decimals), currency, description, category as "Parent > Child",
/// payment method, event, project, comma-separated tags. Defaults are
/// resolved through `displayName` so exports read the same as the UI.
List<List<String>> buildExportRows({
  required List<Expense> expenses,
  required Map<String, Category> categoriesById,
  required Map<String, PaymentMethod> paymentMethodsById,
  required Map<String, Event> eventsById,
  required Map<String, Project> projectsById,
  required Map<String, List<String>> tagIdsByExpenseId,
  required Map<String, Tag> tagsById,
  required Translations translations,
}) {
  final dateFormat = DateFormat('yyyy-MM-dd');

  String categoryPath(String? categoryId) {
    if (categoryId == null) return '';
    final parts = <String>[];
    var current = categoriesById[categoryId];
    while (current != null) {
      parts.insert(0, displayNameFor(translations, name: current.name, isDefault: current.isDefault));
      current = current.parentId == null ? null : categoriesById[current.parentId];
    }
    return parts.join(' > ');
  }

  return [
    for (final e in expenses)
      [
        dateFormat.format(e.date),
        translations.t('expenses.type_${e.type}'),
        (e.amount / 100).toStringAsFixed(2),
        e.currency,
        e.description ?? '',
        categoryPath(e.categoryId),
        e.paymentMethodId == null
            ? ''
            : (paymentMethodsById[e.paymentMethodId] == null
                ? ''
                : displayNameFor(
                    translations,
                    name: paymentMethodsById[e.paymentMethodId]!.name,
                    isDefault: paymentMethodsById[e.paymentMethodId]!.isDefault,
                  )),
        e.eventId == null ? '' : (eventsById[e.eventId]?.name ?? ''),
        e.projectId == null ? '' : (projectsById[e.projectId]?.name ?? ''),
        (tagIdsByExpenseId[e.id] ?? const [])
            .map((tagId) => tagsById[tagId])
            .whereType<Tag>()
            .map((tag) => displayNameFor(translations, name: tag.name, isDefault: tag.isDefault))
            .join(', '),
      ],
  ];
}

const _exportHeader = [
  'Date',
  'Type',
  'Amount',
  'Currency',
  'Description',
  'Category',
  'Payment method',
  'Event',
  'Project',
  'Tags',
];

/// CSV with comma/quote/newline escaping and a UTF-8 BOM so accented
/// characters survive when opened in Excel (plan §9).
String buildExportCsv(List<List<String>> rows) {
  String escape(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  final buffer = StringBuffer('﻿');
  buffer.writeln(_exportHeader.map(escape).join(','));
  for (final row in rows) {
    buffer.writeln(row.map(escape).join(','));
  }
  return buffer.toString();
}

Uint8List encodeCsvUtf8(String csv) => Uint8List.fromList(utf8.encode(csv));

/// Landscape PDF table with a header describing the exported range.
///
/// Uses the bundled Inter font instead of the `pdf` package's default
/// Helvetica, which has no Unicode support — without this, accented
/// characters (á, ñ, ç...) in descriptions/names/tags render as tofu boxes.
Future<Uint8List> buildExportPdf(List<List<String>> rows, {required String rangeLabel}) async {
  final regularFont = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
  final boldFont = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));

  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont));
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (context) => [
        pw.Header(text: 'Transactions - $rangeLabel'),
        pw.TableHelper.fromTextArray(
          headers: _exportHeader,
          data: rows,
          headerStyle: pw.TextStyle(font: boldFont, fontWeight: pw.FontWeight.bold),
          cellStyle: pw.TextStyle(font: regularFont, fontSize: 8),
          cellAlignment: pw.Alignment.centerLeft,
        ),
      ],
    ),
  );
  return doc.save();
}

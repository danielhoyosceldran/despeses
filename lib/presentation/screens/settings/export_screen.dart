import 'dart:developer' as developer;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database.dart';
import '../../../domain/export/export_service.dart';
import '../../../domain/repositories/expense_repository.dart';
import '../../widgets/app_toast.dart';

/// Export (plan §9, inside Settings): month range + type filter, 10-column
/// CSV (BOM + escaping) or landscape PDF, delivered via the share sheet.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String? _type;
  bool _busy = false;

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(context: context, initialDate: _from, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(context: context, initialDate: _to, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null) setState(() => _to = picked);
  }

  /// An inverted range would export an empty file: swap it and say so.
  void _orderDates() {
    if (!_from.isAfter(_to)) return;
    final from = _to;
    setState(() {
      _to = _from;
      _from = from;
    });
    final t = ref.read(translationsProvider).asData?.value;
    showAppToast(
      context,
      t?.t('common.dates_swapped') ?? 'The start date was after the end date, so they were swapped.',
      variant: ToastVariant.warning,
    );
  }

  Future<_ExportData> _buildData() async {
    final expenseRepo = ref.read(expenseRepositoryProvider);
    final expenses = await expenseRepo.listAll(
      filters: ExpenseFilters(type: _type, dateFrom: _from, dateTo: _to),
    );

    final translations = await ref.read(translationsProvider.future);
    final cache = ref.read(referenceDataCacheProvider);
    final categoriesById = {for (final c in await cache.categories()) c.id: c};
    final paymentMethodsById = {for (final m in await cache.paymentMethods()) m.id: m};
    final eventsById = {for (final e in await cache.events()) e.id: e};
    final projectsById = {for (final p in await cache.projects()) p.id: p};
    final tagsById = {for (final t in await cache.tags()) t.id: t};

    final tagIdsByExpenseId = await expenseRepo.tagIdsByExpense(expenses.map((e) => e.id));

    final rows = buildExportRows(
      expenses: expenses,
      categoriesById: categoriesById,
      paymentMethodsById: paymentMethodsById,
      eventsById: eventsById,
      projectsById: projectsById,
      tagIdsByExpenseId: tagIdsByExpenseId,
      tagsById: tagsById,
      translations: translations,
    );
    return _ExportData(translations: translations, expenses: expenses, rows: rows);
  }

  static const _exportFilePrefix = 'despeses_export_';

  /// Writes a uniquely named export file to the temp dir (so a previous export
  /// is never reshared). The file is deliberately NOT deleted after sharing:
  /// on Android `shareXFiles` can resolve before the target app (Gmail, Drive)
  /// has read the attachment. Instead, exports left over from earlier runs are
  /// cleaned up here, at the start of the next export.
  Future<File> _writeExportFile(String extension, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    await for (final entry in dir.list()) {
      if (entry is File && p.basename(entry.path).startsWith(_exportFilePrefix)) {
        try {
          await entry.delete();
        } catch (_) {
          // Best effort: a leftover temp file is harmless.
        }
      }
    }
    final file = File(p.join(dir.path, '$_exportFilePrefix${DateTime.now().millisecondsSinceEpoch}.$extension'));
    return file.writeAsBytes(bytes);
  }

  String get _rangeLabel => '${DateFormat.yMMMd().format(_from)} - ${DateFormat.yMMMd().format(_to)}';

  Future<void> _exportCsv() async {
    _orderDates();
    setState(() => _busy = true);
    try {
      final data = await _buildData();
      final csv = buildExportCsv(
        data.rows,
        header: buildExportHeader(data.translations),
        format: CsvFormat.forLocale(data.translations.locale),
      );
      final file = await _writeExportFile('csv', encodeCsvUtf8(csv));
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e, st) {
      developer.log('export failed', name: 'ExportScreen', error: e, stackTrace: st);
      if (mounted) {
        final t = ref.read(translationsProvider).asData?.value;
        showAppToast(context, t?.t('export.export_failed') ?? 'Export failed. Please try again.', variant: ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPdf() async {
    _orderDates();
    setState(() => _busy = true);
    try {
      final data = await _buildData();
      final bytes = await buildExportPdf(
        data.rows,
        rangeLabel: _rangeLabel,
        header: buildExportHeader(data.translations),
        title: data.translations.t('analytics.transactions'),
        totals: buildExportTotals(expenses: data.expenses, translations: data.translations),
      );
      final file = await _writeExportFile('pdf', bytes);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e, st) {
      developer.log('export failed', name: 'ExportScreen', error: e, stackTrace: st);
      if (mounted) {
        final t = ref.read(translationsProvider).asData?.value;
        showAppToast(context, t?.t('export.export_failed') ?? 'Export failed. Please try again.', variant: ToastVariant.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final t = translationsAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _pickFrom,
                    child: Text('${t?.t('analytics.from') ?? 'From'}: ${DateFormat.yMMMd().format(_from)}'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _pickTo,
                    child: Text('${t?.t('analytics.to') ?? 'To'}: ${DateFormat.yMMMd().format(_to)}'),
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<String?>(
              initialValue: _type,
              decoration: InputDecoration(labelText: t?.t('export.type_filter') ?? 'Type'),
              items: [
                DropdownMenuItem(value: null, child: Text(t?.t('export.all_types') ?? 'All types')),
                DropdownMenuItem(value: 'expense', child: Text(t?.t('expenses.type_expense') ?? 'Expense')),
                DropdownMenuItem(value: 'income', child: Text(t?.t('expenses.type_income') ?? 'Income')),
                DropdownMenuItem(value: 'refund', child: Text(t?.t('expenses.type_refund') ?? 'Refund')),
              ],
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _busy ? null : _exportCsv,
              icon: const Icon(LucideIcons.table300),
              label: Text(t?.t('export.export_csv') ?? 'Export CSV'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _busy ? null : _exportPdf,
              icon: const Icon(LucideIcons.fileText300),
              label: Text(t?.t('export.export_pdf') ?? 'Export PDF'),
            ),
            if (_busy) const Padding(padding: EdgeInsets.only(top: AppSpacing.md), child: LinearProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

/// Everything an export needs: the source transactions (for totals), their
/// table rows and the translations they were rendered with.
class _ExportData {
  const _ExportData({required this.translations, required this.expenses, required this.rows});

  final Translations translations;
  final List<Expense> expenses;
  final List<List<String>> rows;
}

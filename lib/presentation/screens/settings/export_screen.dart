import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
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

  Future<List<List<String>>> _buildRows() async {
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

    final tagIdsByExpenseId = <String, List<String>>{};
    for (final e in expenses) {
      tagIdsByExpenseId[e.id] = await expenseRepo.tagIdsOf(e.id);
    }

    return buildExportRows(
      expenses: expenses,
      categoriesById: categoriesById,
      paymentMethodsById: paymentMethodsById,
      eventsById: eventsById,
      projectsById: projectsById,
      tagIdsByExpenseId: tagIdsByExpenseId,
      tagsById: tagsById,
      translations: translations,
    );
  }

  String get _rangeLabel => '${DateFormat.yMMMd().format(_from)} - ${DateFormat.yMMMd().format(_to)}';

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final rows = await _buildRows();
      final csv = buildExportCsv(rows);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'despeses_export.csv'));
      await file.writeAsBytes(encodeCsvUtf8(csv));
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (mounted) showAppToast(context, 'Export failed: $e', variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _busy = true);
    try {
      final rows = await _buildRows();
      final bytes = await buildExportPdf(rows, rangeLabel: _rangeLabel);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'despeses_export.pdf'));
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (mounted) showAppToast(context, 'Export failed: $e', variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final t = translationsAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(title: Text(t?.t('settings_nav.export') ?? 'Export')),
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
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: null, child: Text('All types')),
                DropdownMenuItem(value: 'expense', child: Text('Expense')),
                DropdownMenuItem(value: 'income', child: Text('Income')),
                DropdownMenuItem(value: 'refund', child: Text('Refund')),
              ],
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _busy ? null : _exportCsv,
              icon: const Icon(LucideIcons.table300),
              label: const Text('Export CSV'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _busy ? null : _exportPdf,
              icon: const Icon(LucideIcons.fileText300),
              label: const Text('Export PDF'),
            ),
            if (_busy) const Padding(padding: EdgeInsets.only(top: AppSpacing.md), child: LinearProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/format/date.dart';
import '../../core/i18n/display_name.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/expense_repository.dart';

/// Filter sheet for the Expenses list (plan §3.4): every filter here is
/// applied entirely in SQL by `ExpenseRepository.list` — no client-side
/// "partial filter" warning like the web app has.
Future<ExpenseFilters?> showExpenseFilterSheet(
  BuildContext context, {
  required ExpenseFilters initial,
  required List<Category> categories,
  required List<Tag> tags,
  required List<PaymentMethod> paymentMethods,
  required List<Event> events,
  required List<Project> projects,
  required Translations translations,
}) {
  return showModalBottomSheet<ExpenseFilters>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ExpenseFilterSheet(
      initial: initial,
      categories: categories,
      tags: tags,
      paymentMethods: paymentMethods,
      events: events,
      projects: projects,
      translations: translations,
    ),
  );
}

class _ExpenseFilterSheet extends StatefulWidget {
  const _ExpenseFilterSheet({
    required this.initial,
    required this.categories,
    required this.tags,
    required this.paymentMethods,
    required this.events,
    required this.projects,
    required this.translations,
  });

  final ExpenseFilters initial;
  final List<Category> categories;
  final List<Tag> tags;
  final List<PaymentMethod> paymentMethods;
  final List<Event> events;
  final List<Project> projects;
  final Translations translations;

  @override
  State<_ExpenseFilterSheet> createState() => _ExpenseFilterSheetState();
}

class _ExpenseFilterSheetState extends State<_ExpenseFilterSheet> {
  late String? _type = widget.initial.type;
  late String? _categoryId = widget.initial.categoryId;
  late String? _tagId = widget.initial.tagId;
  late String? _paymentMethodId = widget.initial.paymentMethodId;
  late String? _eventId = widget.initial.eventId;
  late String? _projectId = widget.initial.projectId;
  late DateTime? _dateFrom = widget.initial.dateFrom;
  late DateTime? _dateTo = widget.initial.dateTo;

  String _label(dynamic entity) => displayNameFor(
        widget.translations,
        name: entity.name as String,
        isDefault: entity.isDefault as bool,
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.translations.t('expenses.filters'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String?>(
              initialValue: _type,
              decoration: InputDecoration(labelText: widget.translations.t('expenses.type')),
              items: [
                DropdownMenuItem(value: null, child: Text(widget.translations.t('common.any'))),
                DropdownMenuItem(value: 'expense', child: Text(widget.translations.t('expenses.type_expense'))),
                DropdownMenuItem(value: 'income', child: Text(widget.translations.t('expenses.type_income'))),
                DropdownMenuItem(value: 'refund', child: Text(widget.translations.t('expenses.type_refund'))),
              ],
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: AppSpacing.smMd),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: InputDecoration(labelText: widget.translations.t('expenses.category')),
              items: [
                DropdownMenuItem(value: null, child: Text(widget.translations.t('common.any'))),
                for (final c in widget.categories) DropdownMenuItem(value: c.id, child: Text(_label(c))),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: AppSpacing.smMd),
            DropdownButtonFormField<String?>(
              initialValue: _tagId,
              decoration: InputDecoration(labelText: widget.translations.t('expenses.tag')),
              items: [
                DropdownMenuItem(value: null, child: Text(widget.translations.t('common.any'))),
                for (final t in widget.tags) DropdownMenuItem(value: t.id, child: Text(_label(t))),
              ],
              onChanged: (v) => setState(() => _tagId = v),
            ),
            const SizedBox(height: AppSpacing.smMd),
            DropdownButtonFormField<String?>(
              initialValue: _paymentMethodId,
              decoration: InputDecoration(labelText: widget.translations.t('expenses.payment_method')),
              items: [
                DropdownMenuItem(value: null, child: Text(widget.translations.t('common.any'))),
                for (final p in widget.paymentMethods) DropdownMenuItem(value: p.id, child: Text(_label(p))),
              ],
              onChanged: (v) => setState(() => _paymentMethodId = v),
            ),
            const SizedBox(height: AppSpacing.smMd),
            DropdownButtonFormField<String?>(
              initialValue: _eventId,
              decoration: InputDecoration(labelText: widget.translations.t('expenses.event')),
              items: [
                DropdownMenuItem(value: null, child: Text(widget.translations.t('common.any'))),
                for (final e in widget.events) DropdownMenuItem(value: e.id, child: Text(e.name)),
              ],
              onChanged: (v) => setState(() => _eventId = v),
            ),
            const SizedBox(height: AppSpacing.smMd),
            DropdownButtonFormField<String?>(
              initialValue: _projectId,
              decoration: InputDecoration(labelText: widget.translations.t('expenses.project')),
              items: [
                DropdownMenuItem(value: null, child: Text(widget.translations.t('common.any'))),
                for (final p in widget.projects) DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _projectId = v),
            ),
            const SizedBox(height: AppSpacing.smMd),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dateFrom ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _dateFrom = picked);
                    },
                    child: Text(_dateFrom == null ? widget.translations.t('expenses.date_from') : formatDate(_dateFrom!)),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dateTo ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _dateTo = picked);
                    },
                    child: Text(_dateTo == null ? widget.translations.t('expenses.date_to') : formatDate(_dateTo!)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(const ExpenseFilters()),
                    child: Text(widget.translations.t('expenses.clear_filters')),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      ExpenseFilters(
                        type: _type,
                        categoryId: _categoryId,
                        tagId: _tagId,
                        paymentMethodId: _paymentMethodId,
                        eventId: _eventId,
                        projectId: _projectId,
                        dateFrom: _dateFrom,
                        dateTo: _dateTo,
                      ),
                    ),
                    child: Text(widget.translations.t('common.apply')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

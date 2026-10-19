import 'package:flutter/material.dart';

import '../../core/format/date.dart';
import '../../core/format/money.dart';
import '../../core/i18n/display_name.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/expense_repository.dart';
import '../../domain/search/transaction_search.dart' show parseAmountCents;

/// Advanced filter sheet for the Transactions list: multi-select type,
/// category, tag, payment method, event and project, an amount range and a
/// date range. Every filter here is applied entirely in SQL by
/// `ExpenseRepository`.
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
  late final Set<String> _types = {...widget.initial.types};
  late final Set<String> _categoryIds = {...widget.initial.categoryIds};
  late final Set<String> _tagIds = {...widget.initial.tagIds};
  late final Set<String> _paymentMethodIds = {...widget.initial.paymentMethodIds};
  late final Set<String> _eventIds = {...widget.initial.eventIds};
  late final Set<String> _projectIds = {...widget.initial.projectIds};
  late DateTime? _dateFrom = widget.initial.dateFrom;
  late DateTime? _dateTo = widget.initial.dateTo;
  late final TextEditingController _amountMin = TextEditingController(text: _centsText(widget.initial.amountMin));
  late final TextEditingController _amountMax = TextEditingController(text: _centsText(widget.initial.amountMax));

  Translations get _t => widget.translations;

  static String _centsText(int? cents) => cents == null ? '' : formatDecimal(cents);

  @override
  void dispose() {
    _amountMin.dispose();
    _amountMax.dispose();
    super.dispose();
  }

  String _label(dynamic entity) => displayNameFor(
        _t,
        name: entity.name as String,
        isDefault: entity.isDefault as bool,
      );

  static const _typeOrder = ['expense', 'income', 'refund', 'ahorro'];

  void _toggle(Set<String> set, String id, bool selected) {
    setState(() => selected ? set.add(id) : set.remove(id));
  }

  /// Collapsible section: label + summary of the current selection ("Any" or
  /// the selected names), expanding to [children].
  Widget _section({
    required String title,
    required Set<String> selected,
    required Map<String, String> labelsById,
    required List<Widget> children,
  }) {
    final colors = context.appColors;
    final summary = selected.isEmpty
        ? _t.t('common.any')
        : selected.map((id) => labelsById[id]).whereType<String>().join(', ');
    return Theme(
      // No divider lines above/below the expanded tile.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(title),
        subtitle: Text(
          summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: selected.isEmpty ? colors.textMuted : colors.accent),
        ),
        children: children,
      ),
    );
  }

  Widget _chips(Set<String> selected, Iterable<(String, String)> items) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final (id, label) in items)
          FilterChip(
            label: Text(label),
            selected: selected.contains(id),
            onSelected: (v) => _toggle(selected, id, v),
          ),
      ],
    );
  }

  /// Categories as a tree grouped by transaction type: a header per type,
  /// then each root followed by its descendants, indented by depth. Picking a
  /// parent filters its whole subtree (see `ExpenseRepository`).
  List<Widget> _categoryTree() {
    final colors = context.appColors;
    final byParent = <String?, List<Category>>{};
    // widget.categories is already ordered by position.
    for (final c in widget.categories) {
      (byParent[c.parentId] ??= []).add(c);
    }
    final rows = <Widget>[];
    void addSubtree(Category c, int depth) {
      rows.add(CheckboxListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.only(left: AppSpacing.md * depth),
        value: _categoryIds.contains(c.id),
        title: Text(_label(c)),
        onChanged: (v) => _toggle(_categoryIds, c.id, v ?? false),
      ));
      for (final child in byParent[c.id] ?? const <Category>[]) {
        addSubtree(child, depth + 1);
      }
    }

    for (final type in _typeOrder) {
      final roots = (byParent[null] ?? const <Category>[]).where((c) => c.type == type).toList();
      if (roots.isEmpty) continue;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
        child: Text(_t.t('expenses.type_$type').toUpperCase(), style: appHeaderStyle(colors)),
      ));
      for (final root in roots) {
        addSubtree(root, 0);
      }
    }
    return rows;
  }

  Widget _amountField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }

  Future<void> _pickDate({required bool from}) async {
    final current = from ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => from ? _dateFrom = picked : _dateTo = picked);
  }

  ExpenseFilters _result() => ExpenseFilters(
        types: _types,
        categoryIds: _categoryIds,
        tagIds: _tagIds,
        paymentMethodIds: _paymentMethodIds,
        eventIds: _eventIds,
        projectIds: _projectIds,
        amountMin: parseAmountCents(_amountMin.text),
        amountMax: parseAmountCents(_amountMax.text),
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );

  @override
  Widget build(BuildContext context) {
    final typeLabels = {for (final type in _typeOrder) type: _t.t('expenses.type_$type')};
    final tagLabels = {for (final tag in widget.tags) tag.id: _label(tag)};
    final methodLabels = {for (final m in widget.paymentMethods) m.id: _label(m)};
    final eventLabels = {for (final e in widget.events) e.id: e.name};
    final projectLabels = {for (final p in widget.projects) p.id: p.name};
    final categoryLabels = {for (final c in widget.categories) c.id: _label(c)};

    return SafeArea(
      child: Padding(
        // Lift the sheet above the keyboard while typing an amount.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                child: Text(_t.t('expenses.filters'), style: Theme.of(context).textTheme.headlineSmall),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section(
                        title: _t.t('expenses.type'),
                        selected: _types,
                        labelsById: typeLabels,
                        children: [_chips(_types, typeLabels.entries.map((e) => (e.key, e.value)))],
                      ),
                      _section(
                        title: _t.t('expenses.category'),
                        selected: _categoryIds,
                        labelsById: categoryLabels,
                        children: _categoryTree(),
                      ),
                      _section(
                        title: _t.t('expenses.tags'),
                        selected: _tagIds,
                        labelsById: tagLabels,
                        children: [_chips(_tagIds, tagLabels.entries.map((e) => (e.key, e.value)))],
                      ),
                      _section(
                        title: _t.t('expenses.payment_method'),
                        selected: _paymentMethodIds,
                        labelsById: methodLabels,
                        children: [_chips(_paymentMethodIds, methodLabels.entries.map((e) => (e.key, e.value)))],
                      ),
                      if (widget.events.isNotEmpty)
                        _section(
                          title: _t.t('expenses.event'),
                          selected: _eventIds,
                          labelsById: eventLabels,
                          children: [_chips(_eventIds, eventLabels.entries.map((e) => (e.key, e.value)))],
                        ),
                      if (widget.projects.isNotEmpty)
                        _section(
                          title: _t.t('expenses.project'),
                          selected: _projectIds,
                          labelsById: projectLabels,
                          children: [_chips(_projectIds, projectLabels.entries.map((e) => (e.key, e.value)))],
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(child: _amountField(_amountMin, _t.t('expenses.amount_min'))),
                          const SizedBox(width: AppSpacing.smMd),
                          Expanded(child: _amountField(_amountMax, _t.t('expenses.amount_max'))),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.smMd),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => _pickDate(from: true),
                              child: Text(_dateFrom == null ? _t.t('expenses.date_from') : formatDate(_dateFrom!)),
                            ),
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: () => _pickDate(from: false),
                              child: Text(_dateTo == null ? _t.t('expenses.date_to') : formatDate(_dateTo!)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(const ExpenseFilters()),
                        child: Text(_t.t('expenses.clear_filters')),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(_result()),
                        child: Text(_t.t('common.apply')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/format/date.dart';
import '../../core/format/money.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';

/// Multi-select list of the expenses a refund can be linked to (BL-071):
/// [candidates] are the expenses of the refund's month. Already-linked
/// expenses from another month (the refund's date changed) are listed too, so
/// they can be unchecked. Like tags, selection doesn't auto-advance: the host
/// closes the panel with its own "Next" button.
class ExpenseLinkPickerContent extends StatefulWidget {
  const ExpenseLinkPickerContent({
    super.key,
    required this.candidates,
    required this.initialSelectedIds,
    required this.translations,
    required this.onChanged,
  });

  final List<Expense> candidates;
  final List<String> initialSelectedIds;
  final Translations translations;

  /// Fired on every toggle with the current selection.
  final ValueChanged<List<String>> onChanged;

  @override
  State<ExpenseLinkPickerContent> createState() => _ExpenseLinkPickerContentState();
}

class _ExpenseLinkPickerContentState extends State<ExpenseLinkPickerContent> {
  late final Set<String> _selected = widget.initialSelectedIds.toSet();

  void _toggle(String id, bool selected) {
    setState(() => selected ? _selected.add(id) : _selected.remove(id));
    widget.onChanged(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.translations;
    final candidates = widget.candidates;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(t.t('expenses.linked_expenses'), style: Theme.of(context).textTheme.titleMedium),
        ),
        Expanded(
          child: candidates.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      t.t('expenses.linked_expenses_empty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.appColors.textMuted),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final expense = candidates[index];
                    return CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected.contains(expense.id),
                      onChanged: (value) => _toggle(expense.id, value ?? false),
                      title: Text(expense.description ?? t.t('expenses.type_expense')),
                      subtitle: Text(formatDate(expense.date)),
                      secondary: Text(formatMoney(expense.amount, expense.currency)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

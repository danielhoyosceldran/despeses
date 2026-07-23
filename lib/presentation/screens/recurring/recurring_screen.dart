import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/format/money.dart';
import '../../../core/navigation/bottom_up_route.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_switch.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/drag_up_fab.dart';
import '../../widgets/empty_state.dart';
import '../expense_entry/expense_entry_screen.dart';
import 'recurring_entry_screen.dart';

/// Recurring transactions (feature 3.13). Two stacked sections:
/// - **Pending** — occurrences the materializer produced, awaiting the user's
///   confirm/edit/skip (the "confirm" model chosen for this feature).
/// - **Templates** — the recurring definitions themselves; tap to edit, toggle
///   the switch to pause/resume, long-press to select for deletion.
class RecurringScreen extends ConsumerStatefulWidget {
  const RecurringScreen({super.key});

  @override
  ConsumerState<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends ConsumerState<RecurringScreen> {
  List<Recurring> _templates = [];
  bool _loading = true;
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Only flash the spinner on the initial load; refreshes after a toggle,
    // delete, or entry save keep the current list on screen to avoid a flicker.
    if (_templates.isEmpty) setState(() => _loading = true);
    final templates = await ref.read(recurringRepositoryProvider).listTemplates();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _loading = false;
    });
  }

  void _toggleSelection(Recurring r) {
    setState(() {
      if (_selectedIds.contains(r.id)) {
        _selectedIds.remove(r.id);
      } else {
        _selectedIds.add(r.id);
      }
    });
  }

  Future<void> _openEntry({Recurring? recurring}) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      bottomUpRoute(RecurringEntryScreen(recurring: recurring)),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteSelected(String Function(String) tr) async {
    final count = _selectedIds.length;
    final confirmed = await showConfirmDialog(
      context,
      title: tr('recurring.delete_title'),
      message: tr('recurring.delete_message').replaceAll('{{count}}', '$count'),
      confirmLabel: tr('common.delete'),
      cancelLabel: tr('common.cancel'),
      destructive: true,
    );
    if (!confirmed) return;
    final repo = ref.read(recurringRepositoryProvider);
    for (final id in _selectedIds) {
      await repo.delete(id);
    }
    setState(() => _selectedIds.clear());
    _load();
  }

  Future<void> _confirmOccurrence(RecurringOccurrence occ, String Function(String) tr) async {
    await ref.read(recurringRepositoryProvider).confirm(occ);
    if (mounted) _showToast(tr('recurring.confirmed'));
  }

  Future<void> _editOccurrence(RecurringOccurrence occ) async {
    final repo = ref.read(recurringRepositoryProvider);
    final tagIds = await repo.tagIdsOf(occ.recurringId);
    if (!mounted) return;
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      bottomUpRoute(ExpenseEntryScreen(
        seed: ExpenseSeed(
          type: occ.type,
          amountCents: occ.amount,
          date: occ.dueDate,
          description: occ.description,
          notes: occ.notes,
          categoryId: occ.categoryId,
          paymentMethodId: occ.paymentMethodId,
          eventId: occ.eventId,
          projectId: occ.projectId,
          tagIds: tagIds,
        ),
      )),
    );
    // The entry screen already created the expense; just clear the occurrence.
    if (saved == true) await repo.skip(occ.id);
  }

  Future<void> _skipOccurrence(RecurringOccurrence occ, String Function(String) tr) async {
    await ref.read(recurringRepositoryProvider).skip(occ.id);
    if (mounted) _showToast(tr('recurring.skipped'));
  }

  Future<void> _confirmAll(List<RecurringOccurrence> pending, String Function(String) tr) async {
    final repo = ref.read(recurringRepositoryProvider);
    for (final occ in pending) {
      await repo.confirm(occ);
    }
    if (mounted) _showToast(tr('recurring.confirmed'));
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)));
  }

  Color _typeColor(String type, AppSemanticColors s) => switch (type) {
        'income' => s.income,
        'refund' => s.refund,
        'ahorro' => s.savings,
        _ => s.expense,
      };

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).asData?.value;
    String tr(String k) => t?.t(k) ?? k;
    final pending = ref.watch(pendingRecurringProvider).asData?.value ?? const [];
    final colors = context.appColors;
    final semantic = context.semanticColors;

    return Scaffold(
      floatingActionButton: DragUpFab(
        pageBuilder: (_, close) => RecurringEntryScreen(onClose: close),
        onResult: (saved) {
          if (saved == true) _load();
        },
        child: const Icon(LucideIcons.plus300),
      ),
      body: Column(
        children: [
          AppTopBar(
            title: tr('recurring.title'),
            selectionCount: _selectedIds.length,
            onClearSelection: () => setState(() => _selectedIds.clear()),
            onDeleteSelection: () => _deleteSelected(tr),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
                    children: [
                      if (pending.isNotEmpty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                tr('recurring.pending').toUpperCase(),
                                style: appHeaderStyle(colors),
                              ),
                            ),
                            if (pending.length > 1)
                              TextButton(
                                onPressed: () => _confirmAll(pending, tr),
                                child: Text(tr('recurring.confirm_all')),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (final occ in pending)
                          _PendingCard(
                            occ: occ,
                            currency: occ.currency,
                            amountColor: _typeColor(occ.type, semantic),
                            skipLabel: tr('recurring.skip'),
                            editLabel: tr('common.edit'),
                            confirmLabel: tr('recurring.confirm'),
                            onConfirm: () => _confirmOccurrence(occ, tr),
                            onEdit: () => _editOccurrence(occ),
                            onSkip: () => _skipOccurrence(occ, tr),
                          ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      Text(tr('recurring.templates').toUpperCase(), style: appHeaderStyle(colors)),
                      const SizedBox(height: AppSpacing.sm),
                      if (_templates.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xl),
                          child: EmptyState(tr('recurring.empty')),
                        )
                      else
                        for (final r in _templates)
                          _TemplateCard(
                            key: ValueKey(r.id),
                            recurring: r,
                            currency: r.currency,
                            amountColor: _typeColor(r.type, semantic),
                            selected: _selectedIds.contains(r.id),
                            selectionMode: _selectionMode,
                            frequencyLabel: tr('recurring.freq_${r.frequency}'),
                            nextLabel: tr('recurring.next'),
                            pausedLabel: tr('recurring.paused'),
                            onTap: () => _selectionMode
                                ? _toggleSelection(r)
                                : _openEntry(recurring: r),
                            onLongPress: () => _toggleSelection(r),
                            onToggleActive: (v) async {
                              // Reflect the toggle immediately so the switch
                              // animates on tap instead of waiting for the DB
                              // write + reload round-trip.
                              setState(() {
                                final i = _templates.indexWhere((t) => t.id == r.id);
                                if (i != -1) _templates[i] = _templates[i].copyWith(active: v);
                              });
                              await ref.read(recurringRepositoryProvider).setActive(r.id, v);
                            },
                            onCheckbox: () => _toggleSelection(r),
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// A pending occurrence row: due date + amount, with confirm / edit / skip.
class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.occ,
    required this.currency,
    required this.amountColor,
    required this.skipLabel,
    required this.editLabel,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onEdit,
    required this.onSkip,
  });

  final RecurringOccurrence occ;
  final String currency;
  final Color amountColor;
  final String skipLabel;
  final String editLabel;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(occ.description ?? '—', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat.yMMMd().format(occ.dueDate),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                formatMoney(occ.amount, currency),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: amountColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onSkip,
                icon: const Icon(LucideIcons.x300, size: 16),
                label: Text(skipLabel),
                style: TextButton.styleFrom(foregroundColor: colors.textMuted),
              ),
              const SizedBox(width: AppSpacing.xs),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(LucideIcons.pencil300, size: 16),
                label: Text(editLabel),
              ),
              const SizedBox(width: AppSpacing.xs),
              FilledButton.icon(
                onPressed: onConfirm,
                icon: const Icon(LucideIcons.check300, size: 16),
                label: Text(confirmLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A recurring template row: name + schedule summary, amount, active switch.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    super.key,
    required this.recurring,
    required this.currency,
    required this.amountColor,
    required this.selected,
    required this.selectionMode,
    required this.frequencyLabel,
    required this.nextLabel,
    required this.pausedLabel,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleActive,
    required this.onCheckbox,
  });

  final Recurring recurring;
  final String currency;
  final Color amountColor;
  final bool selected;
  final bool selectionMode;
  final String frequencyLabel;
  final String nextLabel;
  final String pausedLabel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onCheckbox;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final subtitle = recurring.active
        ? '$frequencyLabel · $nextLabel ${DateFormat.yMMMd().format(recurring.nextDate)}'
        : pausedLabel;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: EdgeInsets.zero,
      child: ListTile(
        selected: selected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusCard)),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        leading: selectionMode
            ? Checkbox(value: selected, onChanged: (_) => onCheckbox())
            : null,
        title: Text(
          recurring.description ?? '—',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: recurring.active ? null : colors.textMuted,
              ),
        ),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatMoney(recurring.amount, currency),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: recurring.active ? amountColor : colors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
            if (!selectionMode) ...[
              const SizedBox(width: AppSpacing.md),
              AppSwitch(value: recurring.active, onChanged: onToggleActive),
            ],
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

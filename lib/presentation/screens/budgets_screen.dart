import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../../core/navigation/bottom_up_route.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../widgets/app_card.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/drag_up_fab.dart';
import '../widgets/entity_form_dialog.dart' show chartPalette;
import '../widgets/thin_progress_bar.dart';
import 'budget_entry/budget_entry_screen.dart';

/// Budget list (plan §3.5): progress bar per budget, active/expired filter,
/// CRUD via the rich `BudgetEntryScreen`.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  List<Budget> _budgets = [];
  Map<String, int> _progress = {};
  bool _showActiveOnly = true;
  bool _loading = true;
  String _query = '';
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _toggleSelection(Budget budget) {
    setState(() {
      if (_selectedIds.contains(budget.id)) {
        _selectedIds.remove(budget.id);
      } else {
        _selectedIds.add(budget.id);
      }
    });
  }

  String get _currentMonthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = ref.read(budgetRepositoryProvider);
    final budgets = await repo.listAll();
    final progress = <String, int>{};
    for (final budget in budgets) {
      progress[budget.id] = await repo.calculateProgress(budget);
    }
    if (!mounted) return;
    setState(() {
      _budgets = budgets;
      _progress = progress;
      _loading = false;
    });
  }

  Future<void> _openEntry({Budget? budget}) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      bottomUpRoute(BudgetEntryScreen(budget: budget)),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete budgets',
      message: 'Delete $count selected budget(s)?',
      destructive: true,
    );
    if (!confirmed) return;
    final repo = ref.read(budgetRepositoryProvider);
    for (final id in _selectedIds) {
      await repo.delete(id);
    }
    setState(() => _selectedIds.clear());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(budgetRepositoryProvider);
    final t = ref.watch(translationsProvider).asData?.value;

    final query = _query.trim().toLowerCase();
    final visible = _budgets.where((b) {
      final active = repo.isActiveForMonth(b, _currentMonthKey);
      if (_showActiveOnly ? !active : active) return false;
      return query.isEmpty || b.name.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      floatingActionButton: DragUpFab(
        pageBuilder: (_, close) => BudgetEntryScreen(onClose: close),
        onResult: (saved) {
          if (saved == true) _load();
        },
        child: const Icon(LucideIcons.plus300),
      ),
      body: Column(
        children: [
          AppTopBar(
            title: t?.t('nav.budgets') ?? 'Budgets',
            selectionCount: _selectedIds.length,
            onClearSelection: () => setState(() => _selectedIds.clear()),
            onDeleteSelection: _deleteSelected,
          ),
          if (!_selectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: _SearchPill(onChanged: (v) => setState(() => _query = v))),
                  const SizedBox(width: AppSpacing.sm),
                  TopBarCircleButton(
                    icon: LucideIcons.archive300,
                    color: _showActiveOnly ? null : context.appColors.accent,
                    onTap: () => setState(() => _showActiveOnly = !_showActiveOnly),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? Center(child: Text(_showActiveOnly ? 'No active budgets' : 'No expired budgets'))
                    : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final budget = visible[index];
                    final spent = _progress[budget.id] ?? 0;
                    final ratio = budget.amount == 0 ? 0.0 : (spent / budget.amount).clamp(0.0, 1.0);
                    final over = spent > budget.amount;
                    final semantic = context.semanticColors;
                    final categoryColor = chartPalette[(budget.categoryId ?? budget.id).hashCode % chartPalette.length];
                    final selected = _selectedIds.contains(budget.id);
                    return AppCard(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        selected: selected,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusCard)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                        leading: _selectionMode
                            ? Checkbox(value: selected, onChanged: (_) => _toggleSelection(budget))
                            : null,
                        title: Text(budget.name, style: Theme.of(context).textTheme.labelLarge),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: AppSpacing.sm),
                            ThinProgressBar(value: ratio, fillColor: over ? semantic.over : categoryColor),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${formatMoney(spent, budget.currency)} / ${formatMoney(budget.amount, budget.currency)}',
                              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                    color: over ? semantic.over : null,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                            ),
                          ],
                        ),
                        onLongPress: () => _toggleSelection(budget),
                        onTap: () => _selectionMode ? _toggleSelection(budget) : _openEntry(budget: budget),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

/// Rounded search field (mock: `bg-muted/50 rounded-full`, leading search icon).
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextField(
      onChanged: onChanged,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Search budgets',
        isDense: true,
        filled: true,
        fillColor: colors.mutedFill(0.5),
        prefixIcon: Icon(LucideIcons.search300, size: 16, color: colors.textMuted),
        prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          borderSide: BorderSide(color: colors.accent, width: 1),
        ),
      ),
    );
  }
}

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../../core/navigation/bottom_up_route.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/savings_goal_repository.dart';
import '../widgets/app_card.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/drag_up_fab.dart';
import '../widgets/entity_form_dialog.dart' show chartPalette;
import '../widgets/thin_progress_bar.dart';
import 'budget_entry/budget_entry_screen.dart';
import 'goal_entry/goal_entry_screen.dart';

/// Which of the two goal-like collections is showing.
enum _Tab { budgets, goals }

/// Budgets & goals: a `SegmentedButton` switches between the spend-limit budget
/// list (progress bar filling toward a cap) and the savings-goal list (progress
/// bar filling toward a target). Both live here because they are the same
/// mental model — a target on a category — read in opposite directions.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  _Tab _tab = _Tab.budgets;

  List<Budget> _budgets = [];
  Map<String, int> _progress = {};
  bool _showActiveOnly = true;
  String _query = '';

  List<SavingsGoal> _goals = [];
  Map<String, GoalProgress> _goalProgress = {};

  bool _loading = true;
  final Set<String> _selectedIds = {};

  // Both tabs live in a horizontal PageView (swipe budgets ↔ goals, mirroring
  // the Dashboard's month swipe), kept in sync with the SegmentedButton.
  late final PageController _pageController;

  bool get _selectionMode => _selectedIds.isNotEmpty;

  String get _currentMonthKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _tab.index);
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  /// SegmentedButton tap → animate the PageView; [_onPageChanged] then updates
  /// the tab state (single source of truth for which tab is active).
  void _switchTab(_Tab tab) {
    if (tab == _tab) return;
    _pageController.animateToPage(
      tab.index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _tab = _Tab.values[index];
      _selectedIds.clear();
    });
  }

  /// Loads both collections (budgets + goals) so either page renders instantly
  /// when swiped. Cheap for a personal app's data volume.
  Future<void> _load() async {
    debugPrint('[Budgets] load started');
    setState(() => _loading = true);
    final budgetRepo = ref.read(budgetRepositoryProvider);
    final budgets = await budgetRepo.listAll();
    final progress = <String, int>{};
    for (final b in budgets) {
      progress[b.id] = await budgetRepo.calculateProgress(b);
    }
    final goalRepo = ref.read(savingsGoalRepositoryProvider);
    final goals = await goalRepo.listAll();
    final goalProgress = <String, GoalProgress>{};
    for (final g in goals) {
      goalProgress[g.id] = await goalRepo.calculateProgress(g);
    }
    if (!mounted) return;
    setState(() {
      _budgets = budgets;
      _progress = progress;
      _goals = goals;
      _goalProgress = goalProgress;
      _loading = false;
    });
    debugPrint('[Budgets] load finished: ${budgets.length} budgets, ${goals.length} goals');
  }

  Future<void> _openBudgetEntry({Budget? budget}) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      bottomUpRoute(BudgetEntryScreen(budget: budget)),
    );
    if (saved == true) _load();
  }

  Future<void> _openGoalEntry({SavingsGoal? goal}) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      bottomUpRoute(GoalEntryScreen(goal: goal)),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteSelected(String Function(String) tr) async {
    final count = _selectedIds.length;
    final confirmed = await showConfirmDialog(
      context,
      title: _tab == _Tab.budgets ? tr('budgets.delete_title') : tr('goals.delete_title'),
      message: (_tab == _Tab.budgets ? tr('budgets.delete_message') : tr('goals.delete_message'))
          .replaceAll('{{count}}', '$count'),
      confirmLabel: tr('common.delete'),
      cancelLabel: tr('common.cancel'),
      destructive: true,
    );
    if (!confirmed) return;
    if (_tab == _Tab.budgets) {
      final repo = ref.read(budgetRepositoryProvider);
      for (final id in _selectedIds) {
        await repo.delete(id);
      }
    } else {
      final repo = ref.read(savingsGoalRepositoryProvider);
      for (final id in _selectedIds) {
        await repo.delete(id);
      }
    }
    setState(() => _selectedIds.clear());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).asData?.value;
    String tr(String k) => t?.t(k) ?? k;

    return Scaffold(
      floatingActionButton: _tab == _Tab.budgets
          ? DragUpFab(
              pageBuilder: (_, close) => BudgetEntryScreen(onClose: close),
              onResult: (saved) {
                if (saved == true) _load();
              },
              child: const Icon(LucideIcons.plus300),
            )
          : DragUpFab(
              pageBuilder: (_, close) => GoalEntryScreen(onClose: close),
              onResult: (saved) {
                if (saved == true) _load();
              },
              child: const Icon(LucideIcons.plus300),
            ),
      body: Column(
        children: [
          AppTopBar(
            title: tr('nav.budgets'),
            selectionCount: _selectedIds.length,
            onClearSelection: () => setState(() => _selectedIds.clear()),
            onDeleteSelection: () => _deleteSelected(tr),
            actions: [TopBarCircleButton(icon: LucideIcons.refreshCw300, onTap: _load)],
          ),
          if (!_selectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_Tab>(
                  segments: [
                    ButtonSegment(value: _Tab.budgets, label: Text(tr('budgets.tab_budgets'))),
                    ButtonSegment(value: _Tab.goals, label: Text(tr('budgets.tab_goals'))),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => _switchTab(s.first),
                ),
              ),
            ),
          // Fixed search + archive row, shared by both tabs. Its behaviour
          // follows the active tab: search filters that tab's list by name, and
          // the archive toggle swaps active↔expired budgets / in-progress↔done
          // goals.
          if (!_selectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: _SearchPill(
                      hint: _tab == _Tab.budgets ? tr('budgets.search') : tr('goals.search'),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
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
                : PageView(
                    controller: _pageController,
                    // No page swipe while selecting — the gesture would clash
                    // with the row drag and mixing selections across tabs.
                    physics: _selectionMode ? const NeverScrollableScrollPhysics() : null,
                    onPageChanged: _onPageChanged,
                    children: [
                      _buildBudgetList(tr),
                      _buildGoalList(tr),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetList(String Function(String) tr) {
    final repo = ref.read(budgetRepositoryProvider);
    final query = _query.trim().toLowerCase();
    final visible = _budgets.where((b) {
      final active = repo.isActiveForMonth(b, _currentMonthKey);
      if (_showActiveOnly ? !active : active) return false;
      return query.isEmpty || b.name.toLowerCase().contains(query);
    }).toList();

    if (visible.isEmpty) {
      return Center(child: Text(_showActiveOnly ? tr('budgets.empty') : tr('budgets.no_expired')));
    }
    return ListView.builder(
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
            leading: _selectionMode ? Checkbox(value: selected, onChanged: (_) => _toggleSelection(budget.id)) : null,
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
            onLongPress: () => _toggleSelection(budget.id),
            onTap: () => _selectionMode ? _toggleSelection(budget.id) : _openBudgetEntry(budget: budget),
          ),
        );
      },
    );
  }

  Widget _buildGoalList(String Function(String) tr) {
    final query = _query.trim().toLowerCase();
    // Archive toggle: on = in-progress goals, off = completed (reached) goals —
    // the savings mirror of the budgets active/expired filter.
    final visible = _goals.where((g) {
      final reached = _goalProgress[g.id]?.reached ?? false;
      if (_showActiveOnly ? reached : !reached) return false;
      return query.isEmpty || g.name.toLowerCase().contains(query);
    }).toList();

    if (visible.isEmpty) {
      return Center(child: Text(_showActiveOnly ? tr('goals.empty') : tr('goals.no_completed')));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final goal = visible[index];
        final progress = _goalProgress[goal.id];
        final saved = progress?.saved ?? 0;
        final ratio = progress?.ratio ?? 0.0;
        final reached = progress?.reached ?? false;
        final semantic = context.semanticColors;
        final categoryColor = chartPalette[goal.categoryId.hashCode % chartPalette.length];
        final selected = _selectedIds.contains(goal.id);

        // Pace hint: how much per month is still needed to hit the deadline.
        String? paceLine;
        if (progress?.perMonthNeeded != null && !reached) {
          paceLine = tr('goals.per_month')
              .replaceAll('{{amount}}', formatMoney(progress!.perMonthNeeded!, goal.currency));
        }

        return AppCard(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: EdgeInsets.zero,
          child: ListTile(
            selected: selected,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusCard)),
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            leading: _selectionMode ? Checkbox(value: selected, onChanged: (_) => _toggleSelection(goal.id)) : null,
            title: Row(
              children: [
                Expanded(child: Text(goal.name, style: Theme.of(context).textTheme.labelLarge)),
                if (reached) Icon(LucideIcons.checkCircle2300, size: 16, color: semantic.savings),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                ThinProgressBar(value: ratio, fillColor: reached ? semantic.savings : categoryColor),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${formatMoney(saved, goal.currency)} / ${formatMoney(goal.targetAmount, goal.currency)}',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
                if (paceLine != null)
                  Text(paceLine, style: Theme.of(context).textTheme.bodySmall!.copyWith(color: context.appColors.textMuted)),
              ],
            ),
            onLongPress: () => _toggleSelection(goal.id),
            onTap: () => _selectionMode ? _toggleSelection(goal.id) : _openGoalEntry(goal: goal),
          ),
        );
      },
    );
  }
}

/// Rounded search field (mock: `bg-muted/50 rounded-full`, leading search icon).
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onChanged, required this.hint});

  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextField(
      onChanged: onChanged,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hint,
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

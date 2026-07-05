import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../widgets/confirm_dialog.dart';
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
      MaterialPageRoute(builder: (_) => BudgetEntryScreen(budget: budget)),
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
    final translationsAsync = ref.watch(translationsProvider);
    final t = translationsAsync.asData?.value;
    final repo = ref.read(budgetRepositoryProvider);

    final visible = _budgets.where((b) {
      final active = repo.isActiveForMonth(b, _currentMonthKey);
      return _showActiveOnly ? active : !active;
    }).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : Text(
                (t?.t('nav.budgets') ?? 'Budgets').toUpperCase(),
                style: appHeaderStyle(colors),
              ),
        centerTitle: true,
        leading: _selectionMode
            ? IconButton(icon: const Icon(LucideIcons.x300), onPressed: () => setState(() => _selectedIds.clear()))
            : null,
        actions: _selectionMode
            ? [IconButton(icon: const Icon(LucideIcons.trash2300), onPressed: _deleteSelected)]
            : [
                IconButton(
                  icon: Icon(_showActiveOnly ? LucideIcons.eye300 : LucideIcons.eyeOff300),
                  tooltip: _showActiveOnly ? 'Showing active' : 'Showing expired',
                  onPressed: () => setState(() => _showActiveOnly = !_showActiveOnly),
                ),
              ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _openEntry(), child: const Icon(LucideIcons.plus300)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : visible.isEmpty
              ? Center(child: Text(_showActiveOnly ? 'No active budgets' : 'No expired budgets'))
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final budget = visible[index];
                    final spent = _progress[budget.id] ?? 0;
                    final ratio = budget.amount == 0 ? 0.0 : (spent / budget.amount).clamp(0.0, 1.0);
                    final over = spent > budget.amount;
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    final semantic = isDark ? AppSemanticColors.dark : AppSemanticColors.light;
                    final categoryColor = chartPalette[(budget.categoryId ?? budget.id).hashCode % chartPalette.length];
                    final selected = _selectedIds.contains(budget.id);
                    return Column(
                      children: [
                        ListTile(
                          selected: selected,
                          leading: _selectionMode
                              ? Checkbox(value: selected, onChanged: (_) => _toggleSelection(budget))
                              : null,
                          title: Text(budget.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              ThinProgressBar(value: ratio, fillColor: over ? semantic.over : categoryColor),
                              const SizedBox(height: 4),
                              Text(
                                '${(spent / 100).toStringAsFixed(2)} / ${(budget.amount / 100).toStringAsFixed(2)} ${budget.currency}',
                                style: TextStyle(
                                  color: over ? semantic.over : null,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                          onLongPress: () => _toggleSelection(budget),
                          onTap: () => _selectionMode ? _toggleSelection(budget) : _openEntry(budget: budget),
                        ),
                        Divider(color: colors.divider, height: 1),
                      ],
                    );
                  },
                ),
    );
  }
}

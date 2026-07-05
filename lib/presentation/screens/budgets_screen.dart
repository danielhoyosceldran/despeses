import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../widgets/confirm_dialog.dart';
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
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BudgetEntryScreen(budget: budget)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Budget budget) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete budget',
      message: 'Delete "${budget.name}"?',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(budgetRepositoryProvider).delete(budget.id);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(t?.t('nav.budgets') ?? 'Budgets'),
        actions: [
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
                    return ListTile(
                      title: Text(budget.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: ratio,
                            color: over ? semantic.over : Theme.of(context).colorScheme.primary,
                          ),
                          Text(
                            '${(spent / 100).toStringAsFixed(2)} / ${(budget.amount / 100).toStringAsFixed(2)} ${budget.currency}',
                            style: TextStyle(
                              color: over ? semantic.over : null,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(LucideIcons.trash2300),
                        onPressed: () => _delete(budget),
                      ),
                      onTap: () => _openEntry(budget: budget),
                    );
                  },
                ),
    );
  }
}

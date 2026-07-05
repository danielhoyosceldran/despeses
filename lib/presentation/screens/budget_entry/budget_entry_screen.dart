import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database.dart';
import '../../../domain/repositories/budget_repository.dart';
import '../../widgets/bottom_action_panel.dart';
import '../../widgets/category_picker_sheet.dart';
import '../../widgets/month_picker_dialog.dart';
import '../../widgets/numeric_keypad.dart';
import '../../widgets/simple_picker_sheet.dart';

/// Rich entry for budgets (plan §4), reusing the same keypad/panel pattern
/// as transactions (plan §3). Full-screen, closes with X (not back arrow).
///
/// In edit mode, dimension/type/value are locked — only name and amount can
/// change (plan §4.2), matching `BudgetRepository.updateNameAndAmount`.
class BudgetEntryScreen extends ConsumerStatefulWidget {
  const BudgetEntryScreen({super.key, this.budget});

  final Budget? budget;

  @override
  ConsumerState<BudgetEntryScreen> createState() => _BudgetEntryScreenState();
}

enum _Dimension { category, tag, project, event }

enum _BudgetType { range, months, total }

class _BudgetEntryScreenState extends ConsumerState<BudgetEntryScreen> {
  bool get _isEdit => widget.budget != null;

  final _nameController = TextEditingController();
  int _amountCents = 0;
  _Dimension _dimension = _Dimension.category;
  _BudgetType _type = _BudgetType.total;
  String? _dimensionValueId;
  String? _dimensionValueLabel;
  YearMonth? _startsMonth;
  YearMonth? _endsMonth;
  final List<YearMonth> _months = [];

  String? _openPanel;
  Widget? _panelContent;

  @override
  void initState() {
    super.initState();
    if (widget.budget != null) {
      _hydrate(widget.budget!);
      _resolveDimensionLabel();
    }
  }

  Future<void> _resolveDimensionLabel() async {
    final translations = await ref.read(translationsProvider.future);
    final cache = ref.read(referenceDataCacheProvider);
    String? label;
    switch (_dimension) {
      case _Dimension.category:
        final match = (await cache.categories()).where((c) => c.id == _dimensionValueId);
        if (match.isNotEmpty) {
          label = displayNameFor(translations, name: match.first.name, isDefault: match.first.isDefault);
        }
      case _Dimension.tag:
        final match = (await cache.tags()).where((t) => t.id == _dimensionValueId);
        if (match.isNotEmpty) {
          label = displayNameFor(translations, name: match.first.name, isDefault: match.first.isDefault);
        }
      case _Dimension.project:
        final match = (await cache.projects()).where((p) => p.id == _dimensionValueId);
        if (match.isNotEmpty) label = match.first.name;
      case _Dimension.event:
        final match = (await cache.events()).where((e) => e.id == _dimensionValueId);
        if (match.isNotEmpty) label = match.first.name;
    }
    if (mounted) setState(() => _dimensionValueLabel = label);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _hydrate(Budget budget) {
    _nameController.text = budget.name;
    _amountCents = budget.amount;
    if (budget.categoryId != null) _dimension = _Dimension.category;
    if (budget.tagId != null) _dimension = _Dimension.tag;
    if (budget.projectId != null) _dimension = _Dimension.project;
    if (budget.eventId != null) _dimension = _Dimension.event;
    _dimensionValueId = budget.categoryId ?? budget.tagId ?? budget.projectId ?? budget.eventId;
    _type = switch (budget.budgetType) {
      'range' => _BudgetType.range,
      'months' => _BudgetType.months,
      _ => _BudgetType.total,
    };
    if (budget.startsMonth != null) {
      final parts = budget.startsMonth!.split('-');
      _startsMonth = YearMonth(int.parse(parts[0]), int.parse(parts[1]));
    }
    if (budget.endsMonth != null) {
      final parts = budget.endsMonth!.split('-');
      _endsMonth = YearMonth(int.parse(parts[0]), int.parse(parts[1]));
    }
    if (budget.months != null) {
      final repo = ref.read(budgetRepositoryProvider);
      for (final m in repo.decodeMonths(budget)) {
        _months.add(YearMonth(m.year, m.month));
      }
    }
  }

  void _closePanel() => setState(() {
        _openPanel = null;
        _panelContent = null;
      });

  void _openAmountPanel(String currency) {
    setState(() {
      _openPanel = 'amount';
      _panelContent = null;
    });
  }

  Future<void> _openDimensionValuePanel() async {
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    switch (_dimension) {
      case _Dimension.category:
        setState(() {
          _openPanel = 'dimensionValue';
          _panelContent = CategoryPickerContent(
            repository: ref.read(categoryRepositoryProvider),
            translations: translations,
            onSelected: (selected) {
              setState(() {
                _dimensionValueId = selected.id;
                _dimensionValueLabel = displayNameFor(translations, name: selected.name, isDefault: selected.isDefault);
              });
              _closePanel();
            },
          );
        });
      case _Dimension.tag:
        final tags = await ref.read(referenceDataCacheProvider).tags();
        if (!mounted) return;
        setState(() {
          _openPanel = 'dimensionValue';
          _panelContent = SimplePickerContent<Tag>(
            title: translations.t('budgets.dim_tag'),
            items: tags,
            labelOf: (t) => displayNameFor(translations, name: t.name, isDefault: t.isDefault),
            onSelected: (selected) {
              setState(() {
                _dimensionValueId = selected.id;
                _dimensionValueLabel = displayNameFor(translations, name: selected.name, isDefault: selected.isDefault);
              });
              _closePanel();
            },
          );
        });
      case _Dimension.project:
        final projects = await ref.read(referenceDataCacheProvider).projects();
        if (!mounted) return;
        setState(() {
          _openPanel = 'dimensionValue';
          _panelContent = SimplePickerContent<Project>(
            title: translations.t('budgets.dim_project'),
            items: projects,
            labelOf: (p) => p.name,
            onSelected: (selected) {
              setState(() {
                _dimensionValueId = selected.id;
                _dimensionValueLabel = selected.name;
              });
              _closePanel();
            },
          );
        });
      case _Dimension.event:
        final events = await ref.read(referenceDataCacheProvider).events();
        if (!mounted) return;
        setState(() {
          _openPanel = 'dimensionValue';
          _panelContent = SimplePickerContent<Event>(
            title: translations.t('budgets.dim_event'),
            items: events,
            labelOf: (e) => e.name,
            onSelected: (selected) {
              setState(() {
                _dimensionValueId = selected.id;
                _dimensionValueLabel = selected.name;
              });
              _closePanel();
            },
          );
        });
    }
  }

  void _openMonthPanel({required YearMonth? initial, required ValueChanged<YearMonth> onSelected}) {
    setState(() {
      _openPanel = 'month';
      _panelContent = MonthPickerContent(
        initial: initial,
        onSelected: (picked) {
          onSelected(picked);
          _closePanel();
        },
      );
    });
  }

  bool get _canSave {
    if (_nameController.text.trim().isEmpty) return false;
    if (_amountCents <= 0) return false;
    if (_isEdit) return true;
    if (_dimensionValueId == null) return false;
    return switch (_type) {
      _BudgetType.range => _startsMonth != null,
      _BudgetType.months => _months.isNotEmpty,
      _BudgetType.total => true,
    };
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final repo = ref.read(budgetRepositoryProvider);
    final name = _nameController.text.trim();

    if (_isEdit) {
      await repo.updateNameAndAmount(widget.budget!.id, name: name, amountCents: _amountCents);
    } else {
      final profile = await ref.read(profileRepositoryProvider).get();
      await repo.create(
        name: name,
        categoryId: _dimension == _Dimension.category ? _dimensionValueId : null,
        tagId: _dimension == _Dimension.tag ? _dimensionValueId : null,
        projectId: _dimension == _Dimension.project ? _dimensionValueId : null,
        eventId: _dimension == _Dimension.event ? _dimensionValueId : null,
        amountCents: _amountCents,
        currency: profile.currency,
        budgetType: switch (_type) {
          _BudgetType.range => 'range',
          _BudgetType.months => 'months',
          _BudgetType.total => 'total',
        },
        months: _type == _BudgetType.months ? _months.map((m) => BudgetMonth(m.year, m.month)).toList() : null,
        startsMonth: _type == _BudgetType.range ? _startsMonth?.key : null,
        endsMonth: _type == _BudgetType.range ? _endsMonth?.key : null,
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;
    final profileAsync = ref.watch(profileStreamProvider);
    final currency = profileAsync.asData?.value.currency ?? 'EUR';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(LucideIcons.x300), onPressed: () => Navigator.of(context).pop()),
        title: Text(_isEdit ? (translations?.t('budgets.edit') ?? 'Edit budget') : (translations?.t('budgets.new') ?? 'New budget')),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: translations?.t('common.name') ?? 'Name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.euro300, color: colors.accent),
                  title: Text(translations?.t('budgets.limit') ?? 'Limit'),
                  trailing: Text(
                    '${(_amountCents / 100).toStringAsFixed(2)} $currency',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  onTap: () => _openAmountPanel(currency),
                ),
                const SizedBox(height: 16),
                Text(translations?.t('budgets.dimension') ?? 'Dimension', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<_Dimension>(
                  segments: [
                    ButtonSegment(value: _Dimension.category, label: Text(translations?.t('budgets.dim_category') ?? 'Category')),
                    ButtonSegment(value: _Dimension.tag, label: Text(translations?.t('budgets.dim_tag') ?? 'Tag')),
                    ButtonSegment(value: _Dimension.project, label: Text(translations?.t('budgets.dim_project') ?? 'Project')),
                    ButtonSegment(value: _Dimension.event, label: Text(translations?.t('budgets.dim_event') ?? 'Event')),
                  ],
                  selected: {_dimension},
                  onSelectionChanged: _isEdit
                      ? null
                      : (s) => setState(() {
                            _dimension = s.first;
                            _dimensionValueId = null;
                            _dimensionValueLabel = null;
                          }),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _dimensionValueLabel ?? (translations?.t('budgets.select_value') ?? 'Select value'),
                    style: TextStyle(color: _isEdit ? colors.textDisabled : colors.text),
                  ),
                  trailing: Icon(LucideIcons.chevronRight300, color: _isEdit ? colors.textDisabled : colors.accent),
                  onTap: _isEdit ? null : _openDimensionValuePanel,
                ),
                const SizedBox(height: 16),
                Text(translations?.t('budgets.type') ?? 'Budget type', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<_BudgetType>(
                  segments: [
                    ButtonSegment(value: _BudgetType.range, label: Text(translations?.t('budgets.type_range') ?? 'Range')),
                    ButtonSegment(value: _BudgetType.months, label: Text(translations?.t('budgets.type_months') ?? 'Months')),
                    ButtonSegment(value: _BudgetType.total, label: Text(translations?.t('budgets.type_total') ?? 'Total')),
                  ],
                  selected: {_type},
                  onSelectionChanged: _isEdit ? null : (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: 8),
                if (_type == _BudgetType.range) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_startsMonth == null ? (translations?.t('budgets.starts_month') ?? 'Start month') : _startsMonth!.key),
                    trailing: Icon(LucideIcons.chevronRight300, color: _isEdit ? colors.textDisabled : colors.accent),
                    onTap: _isEdit
                        ? null
                        : () => _openMonthPanel(
                              initial: _startsMonth,
                              onSelected: (picked) => setState(() => _startsMonth = picked),
                            ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _endsMonth == null
                          ? '${translations?.t('budgets.ends_month') ?? 'End month'} (${translations?.t('budgets.optional') ?? 'optional'})'
                          : _endsMonth!.key,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_endsMonth != null && !_isEdit)
                          IconButton(icon: const Icon(LucideIcons.x300), onPressed: () => setState(() => _endsMonth = null)),
                        Icon(LucideIcons.chevronRight300, color: _isEdit ? colors.textDisabled : colors.accent),
                      ],
                    ),
                    onTap: _isEdit
                        ? null
                        : () => _openMonthPanel(
                              initial: _endsMonth,
                              onSelected: (picked) => setState(() => _endsMonth = picked),
                            ),
                  ),
                ],
                if (_type == _BudgetType.months) ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in _months)
                        Chip(
                          label: Text(m.key),
                          onDeleted: _isEdit ? null : () => setState(() => _months.remove(m)),
                        ),
                      if (!_isEdit)
                        ActionChip(
                          label: Text(translations?.t('budgets.add_month') ?? 'Add month'),
                          onPressed: () => _openMonthPanel(
                            initial: null,
                            onSelected: (picked) {
                              if (!_months.contains(picked)) setState(() => _months.add(picked));
                            },
                          ),
                        ),
                    ],
                  ),
                ],
                if (_type == _BudgetType.total)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      translations?.t('budgets.type_total_hint') ?? 'Tracks spending against the limit with no time boundary.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          BottomActionPanel(
            isOpen: _openPanel != null,
            maxHeight: _openPanel == 'amount' ? 400 : 340,
            child: _openPanel == 'amount'
                ? NumericKeypad(
                    amountCents: _amountCents,
                    currency: currency,
                    nextLabel: translations?.t('common.next') ?? 'Next',
                    onAmountChanged: (v) => setState(() => _amountCents = v),
                    onNext: _closePanel,
                  )
                : _panelContent,
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _canSave ? _save : null, child: Text(translations?.t('common.save') ?? 'Save')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

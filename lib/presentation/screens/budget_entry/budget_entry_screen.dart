import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/haptics.dart';
import '../../../core/i18n/display_name.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/bottom_action_panel.dart';
import '../../widgets/category_picker_sheet.dart';
import '../../widgets/month_picker_dialog.dart';
import '../../widgets/numeric_keypad.dart';
import '../../widgets/simple_picker_sheet.dart';
import '../../widgets/swipe_down_to_close.dart';

/// Rich entry for budgets (plan §4), reusing the same keypad/panel pattern
/// as transactions (plan §3). Full-screen, closes with X (not back arrow).
///
/// In edit mode, dimension/type/value are locked — only name and amount can
/// change (plan §4.2), matching `BudgetRepository.updateNameAndAmount`.
class BudgetEntryScreen extends ConsumerStatefulWidget {
  const BudgetEntryScreen({super.key, this.budget, this.onClose});

  final Budget? budget;

  /// Overlay-mode close hook. When null the screen closes via `Navigator.pop`
  /// (pushed as a route); when set — e.g. the interactive drag-up sheet —
  /// closing is delegated so the host can animate it away.
  final void Function(Object? result)? onClose;

  @override
  ConsumerState<BudgetEntryScreen> createState() => _BudgetEntryScreenState();
}

enum _Dimension { category, tag, project, event }

enum _BudgetType { monthly, range }

class _BudgetEntryScreenState extends ConsumerState<BudgetEntryScreen> {
  bool get _isEdit => widget.budget != null;

  /// Project/event budgets have a fixed period == the entity's duration, so the
  /// user doesn't pick a period type for them.
  bool get _isEntityDimension => _dimension == _Dimension.project || _dimension == _Dimension.event;

  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  int _amountCents = 0;
  _Dimension _dimension = _Dimension.category;
  _BudgetType _type = _BudgetType.monthly;
  String? _dimensionValueId;
  String? _dimensionValueLabel;
  YearMonth? _startsMonth;
  YearMonth? _endsMonth;

  String? _openPanel;
  Widget? _panelContent;

  @override
  void initState() {
    super.initState();
    if (widget.budget != null) {
      _hydrate(widget.budget!);
      _resolveDimensionLabel();
    } else {
      // New budget: open the keypad first so the flow starts at the amount.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAmountPanel(''));
    }
    // Focusing the name field must dismiss any open bottom panel (keypad/month
    // picker) so the OS keyboard doesn't stack on top of it.
    _nameFocus.addListener(() {
      if (_nameFocus.hasFocus && _openPanel != null) _closePanel();
    });
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
    _nameFocus.dispose();
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
      _ => _BudgetType.monthly,
    };
    if (budget.startsMonth != null) {
      final parts = budget.startsMonth!.split('-');
      _startsMonth = YearMonth(int.parse(parts[0]), int.parse(parts[1]));
    }
    if (budget.endsMonth != null) {
      final parts = budget.endsMonth!.split('-');
      _endsMonth = YearMonth(int.parse(parts[0]), int.parse(parts[1]));
    }
  }

  void _closePanel() => setState(() {
        _openPanel = null;
        _panelContent = null;
      });

  /// Opening a bottom panel must drop the name field's focus so the OS keyboard
  /// hides (otherwise it stacks on top of the panel).
  void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  void _openAmountPanel(String currency) {
    _dismissKeyboard();
    setState(() {
      _openPanel = 'amount';
      _panelContent = null;
    });
  }

  Future<void> _openDimensionValuePanel() async {
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    _dismissKeyboard();
    switch (_dimension) {
      case _Dimension.category:
        setState(() {
          _openPanel = 'dimensionValue';
          _panelContent = CategoryPickerContent(
            repository: ref.read(categoryRepositoryProvider),
            translations: translations,
            // Budgets track spend, so they scope over the expense category tree.
            type: 'expense',
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
                _applyEntityPeriod(selected.startsAt, selected.endsAt);
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
                _applyEntityPeriod(selected.startsAt, selected.endsAt);
              });
              _closePanel();
            },
          );
        });
    }
  }

  /// Project/event budgets take their period from the entity's own duration
  /// (fixed, not user-chosen). Snapshot its start/end months; leaving either
  /// null when the entity has no dates blocks the save (period is undefined).
  void _applyEntityPeriod(DateTime? startsAt, DateTime? endsAt) {
    _startsMonth = startsAt == null ? null : YearMonth(startsAt.year, startsAt.month);
    _endsMonth = endsAt == null ? null : YearMonth(endsAt.year, endsAt.month);
  }

  void _openMonthPanel({required YearMonth? initial, required ValueChanged<YearMonth> onSelected}) {
    _dismissKeyboard();
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
    // Project/event: fixed period from the entity — needs both of its dates.
    if (_isEntityDimension) return _startsMonth != null && _endsMonth != null;
    return switch (_type) {
      _BudgetType.monthly => true,
      _BudgetType.range => _startsMonth != null && _endsMonth != null,
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
        // Project/event budgets are always a fixed range (the entity duration).
        budgetType: _isEntityDimension
            ? 'range'
            : switch (_type) {
                _BudgetType.monthly => 'monthly',
                _BudgetType.range => 'range',
              },
        startsMonth: (_isEntityDimension || _type == _BudgetType.range) ? _startsMonth?.key : null,
        endsMonth: (_isEntityDimension || _type == _BudgetType.range) ? _endsMonth?.key : null,
      );
    }
    _close(true);
  }

  /// Close the screen, routing through [BudgetEntryScreen.onClose] when hosted
  /// as an overlay sheet, else popping the route.
  void _close([Object? result]) {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose(result);
    } else if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  /// Uppercase muted section header (STYLE §2.2 `appHeaderStyle`).
  Widget _sectionLabel(String text) =>
      Text(text.toUpperCase(), style: appHeaderStyle(context.appColors));

  void _selectDimension(_Dimension d) => setState(() {
        _dimension = d;
        _dimensionValueId = null;
        _dimensionValueLabel = null;
        // Period bounds only apply to range/entity; clear so a stale entity
        // window can't leak into a category/tag budget.
        _startsMonth = null;
        _endsMonth = null;
      });

  /// The dimension picker as a 2×2 grid of toggle cells (plan §4). Locked in
  /// edit mode — the dimension can't change once the budget exists.
  Widget _dimensionGrid(Translations? translations, AppColors colors) {
    final cells = <(_Dimension, String)>[
      (_Dimension.category, translations?.t('budgets.dim_category') ?? 'Category'),
      (_Dimension.tag, translations?.t('budgets.dim_tag') ?? 'Tag'),
      (_Dimension.project, translations?.t('budgets.dim_project') ?? 'Project'),
      (_Dimension.event, translations?.t('budgets.dim_event') ?? 'Event'),
    ];
    Widget cell(int i) => Expanded(child: _trackCell(label: cells[i].$2, selected: _dimension == cells[i].$1, onTap: _isEdit ? null : () => _selectDimension(cells[i].$1)));
    return Column(
      children: [
        Row(children: [cell(0), const SizedBox(width: AppSpacing.sm), cell(1)]),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [cell(2), const SizedBox(width: AppSpacing.sm), cell(3)]),
      ],
    );
  }

  Widget _trackCell({required String label, required bool selected, VoidCallback? onTap}) {
    final colors = context.appColors;
    final disabled = onTap == null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDimens.animFast,
        curve: AppDimens.animCurve,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusBudget),
          border: Border.all(color: selected ? colors.accent : colors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: disabled ? colors.textDisabled : (selected ? colors.onAccent : colors.text),
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  /// Compact tappable field row for a card group — value or muted placeholder +
  /// trailing chevron. `onTap: null` renders it disabled (locked in edit mode).
  Widget _fieldTile({required String text, required bool isPlaceholder, VoidCallback? onTap}) {
    final colors = context.appColors;
    final disabled = onTap == null;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      title: Text(
        text,
        style: TextStyle(
          color: disabled ? colors.textDisabled : (isPlaceholder ? colors.textMuted : colors.text),
        ),
      ),
      trailing: Icon(LucideIcons.chevronRight300, size: 18, color: disabled ? colors.textDisabled : colors.accent),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;
    final profileAsync = ref.watch(profileStreamProvider);
    final currency = profileAsync.asData?.value.currency ?? 'EUR';
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(LucideIcons.chevronDown300), onPressed: () => _close()),
        title: Text(_isEdit ? (translations?.t('budgets.edit') ?? 'Edit budget') : (translations?.t('budgets.new') ?? 'New budget')),
      ),
      body: Column(
        children: [
          Expanded(
            child: SwipeDownToClose(
              onClose: _close,
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
              children: [
                // Limit hero — the money value, Clash display, tap to open keypad.
                Center(child: Text((translations?.t('budgets.limit') ?? 'Limit').toUpperCase(), style: appHeaderStyle(colors))),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openAmountPanel(currency),
                    child: AmountText(amountCents: _amountCents, currency: currency, color: colors.text),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Name — the themed input carries its own filled surface; no
                // wrapping card (its border would double up with the input's).
                TextField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  decoration: InputDecoration(labelText: translations?.t('common.name') ?? 'Name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Tracks (dimension)
                _sectionLabel(translations?.t('budgets.dimension') ?? 'Tracks'),
                const SizedBox(height: AppSpacing.sm),
                _dimensionGrid(translations, colors),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  clip: true,
                  padding: EdgeInsets.zero,
                  child: _fieldTile(
                    text: _dimensionValueLabel ?? (translations?.t('budgets.select_value') ?? 'Select value'),
                    isPlaceholder: _dimensionValueLabel == null,
                    onTap: _isEdit ? null : _openDimensionValuePanel,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Period
                _sectionLabel(translations?.t('budgets.type') ?? 'Period'),
                const SizedBox(height: AppSpacing.sm),
                // Project/event budgets: period is fixed to the entity's own
                // duration — no type picker, just a read-only summary (or a
                // warning if the entity has no start/end dates).
                if (_isEntityDimension) ...[
                  if (_startsMonth != null && _endsMonth != null) ...[
                    AppCard(
                      clip: true,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _fieldTile(text: '${translations?.t('budgets.starts_month') ?? 'From'}  ·  ${_startsMonth!.key}', isPlaceholder: false),
                          Divider(height: 1, color: colors.divider),
                          _fieldTile(text: '${translations?.t('budgets.ends_month') ?? 'Until'}  ·  ${_endsMonth!.key}', isPlaceholder: false),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: Text(
                        translations?.t('budgets.period_auto_hint') ?? 'Fixed to the event or project duration.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
                      child: Text(
                        _dimensionValueId == null
                            ? (translations?.t('budgets.period_auto_hint') ?? 'Fixed to the event or project duration.')
                            : (translations?.t('budgets.entity_no_dates') ?? 'This event or project has no start/end dates. Add them first to budget it.'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ] else ...[
                  SegmentedButton<_BudgetType>(
                    segments: [
                      ButtonSegment(value: _BudgetType.monthly, label: Text(translations?.t('budgets.type_monthly') ?? 'Monthly')),
                      ButtonSegment(value: _BudgetType.range, label: Text(translations?.t('budgets.type_range') ?? 'Range')),
                    ],
                    selected: {_type},
                    onSelectionChanged: _isEdit ? null : (s) => setState(() => _type = s.first),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_type == _BudgetType.monthly)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
                      child: Text(
                        translations?.t('budgets.type_monthly_hint') ?? 'Recurs every month: this limit applies to each month on its own.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (_type == _BudgetType.range)
                    AppCard(
                      clip: true,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _fieldTile(
                            text: _startsMonth == null ? (translations?.t('budgets.starts_month') ?? 'From') : _startsMonth!.key,
                            isPlaceholder: _startsMonth == null,
                            onTap: _isEdit
                                ? null
                                : () => _openMonthPanel(
                                      initial: _startsMonth,
                                      onSelected: (picked) => setState(() => _startsMonth = picked),
                                    ),
                          ),
                          Divider(height: 1, color: colors.divider),
                          _fieldTile(
                            text: _endsMonth == null ? (translations?.t('budgets.ends_month') ?? 'Until') : _endsMonth!.key,
                            isPlaceholder: _endsMonth == null,
                            onTap: _isEdit
                                ? null
                                : () => _openMonthPanel(
                                      initial: _endsMonth,
                                      onSelected: (picked) => setState(() => _endsMonth = picked),
                                    ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
              ),
            ),
          ),
          if (_openPanel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _canSave ? _save : null, child: Text(translations?.t('common.save') ?? 'Save')),
              ),
            ),
          BottomActionPanel(
            isOpen: _openPanel != null,
            maxHeight: switch (_openPanel) {
                  'month' => 380,
                  _ => 340,
                } +
                MediaQuery.of(context).padding.bottom,
            child: _openPanel == 'amount'
                ? NumericKeypad(
                    amountCents: _amountCents,
                    nextLabel: translations?.t('common.next') ?? 'Next',
                    onKeyTap: () => ref.read(hapticsProvider).selection(),
                    onAmountChanged: (v) => setState(() => _amountCents = v),
                    // Auto-advance chain: amount → name, then stop. Dimension,
                    // value and period are chosen manually by the user.
                    onNext: () {
                      _closePanel();
                      _nameFocus.requestFocus();
                    },
                  )
                : _panelContent,
          ),
          if (_openPanel == null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
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

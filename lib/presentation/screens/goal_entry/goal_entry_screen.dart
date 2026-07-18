import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/haptics/haptics.dart';
import '../../../core/i18n/display_name.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/bottom_action_panel.dart';
import '../../widgets/calendar_panel.dart';
import '../../widgets/category_picker_sheet.dart';
import '../../widgets/numeric_keypad.dart';
import '../../widgets/swipe_down_to_close.dart';

/// Create/edit a savings goal (feature 3.14). Reuses the budget entry pattern
/// (keypad + panels). The linked savings category and currency are locked once
/// the goal exists — only name, target and deadline stay editable — mirroring
/// how a budget's dimension is frozen after creation.
class GoalEntryScreen extends ConsumerStatefulWidget {
  const GoalEntryScreen({super.key, this.goal, this.onClose});

  final SavingsGoal? goal;

  /// Overlay-mode close hook (see the other entry screens).
  final void Function(Object? result)? onClose;

  @override
  ConsumerState<GoalEntryScreen> createState() => _GoalEntryScreenState();
}

class _GoalEntryScreenState extends ConsumerState<GoalEntryScreen> {
  bool get _isEdit => widget.goal != null;

  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  int _targetCents = 0;
  String? _categoryId;
  String? _categoryLabel;
  DateTime? _deadline;

  String? _openPanel;
  Widget? _panelContent;

  @override
  void initState() {
    super.initState();
    if (widget.goal != null) {
      _hydrate(widget.goal!);
      _resolveCategoryLabel();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAmountPanel());
    }
    _nameFocus.addListener(() {
      if (_nameFocus.hasFocus && _openPanel != null) _closePanel();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _hydrate(SavingsGoal goal) {
    _nameController.text = goal.name;
    _targetCents = goal.targetAmount;
    _categoryId = goal.categoryId;
    _deadline = goal.deadline;
  }

  Future<void> _resolveCategoryLabel() async {
    final translations = await ref.read(translationsProvider.future);
    final match = (await ref.read(referenceDataCacheProvider).categories())
        .where((c) => c.id == _categoryId);
    if (match.isNotEmpty && mounted) {
      setState(() => _categoryLabel =
          displayNameFor(translations, name: match.first.name, isDefault: match.first.isDefault));
    }
  }

  void _closePanel() => setState(() {
        _openPanel = null;
        _panelContent = null;
      });

  void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  void _openAmountPanel() {
    _dismissKeyboard();
    setState(() {
      _openPanel = 'amount';
      _panelContent = null;
    });
  }

  Future<void> _openCategoryPanel() async {
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    _dismissKeyboard();
    setState(() {
      _openPanel = 'category';
      _panelContent = CategoryPickerContent(
        repository: ref.read(categoryRepositoryProvider),
        translations: translations,
        // Goals track savings, so they scope over the `ahorro` category tree.
        type: 'ahorro',
        onSelected: (selected) {
          ref.read(hapticsProvider).selection();
          setState(() {
            _categoryId = selected.id;
            _categoryLabel =
                displayNameFor(translations, name: selected.name, isDefault: selected.isDefault);
          });
          _closePanel();
        },
      );
    });
  }

  void _openDeadlinePanel() {
    _dismissKeyboard();
    setState(() {
      _openPanel = 'deadline';
      _panelContent = CalendarPanel(
        initial: _deadline ?? DateTime.now(),
        onSelected: (picked) {
          ref.read(hapticsProvider).selection();
          setState(() => _deadline = picked);
          _closePanel();
        },
      );
    });
  }

  bool get _canSave {
    if (_nameController.text.trim().isEmpty) return false;
    if (_targetCents <= 0) return false;
    if (_isEdit) return true;
    return _categoryId != null;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final repo = ref.read(savingsGoalRepositoryProvider);
    final name = _nameController.text.trim();
    if (_isEdit) {
      await repo.update(
        widget.goal!.id,
        name: name,
        targetCents: _targetCents,
        deadline: _deadline,
        clearDeadline: _deadline == null,
      );
    } else {
      final profile = await ref.read(profileRepositoryProvider).get();
      await repo.create(
        name: name,
        categoryId: _categoryId!,
        targetCents: _targetCents,
        currency: profile.currency,
        deadline: _deadline,
      );
    }
    _close(true);
  }

  void _close([Object? result]) {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose(result);
    } else if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Widget _sectionLabel(String text) =>
      Text(text.toUpperCase(), style: appHeaderStyle(context.appColors));

  Widget _fieldTile({
    required String text,
    required bool isPlaceholder,
    VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
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
      trailing: onClear != null
          ? IconButton(icon: Icon(LucideIcons.x300, size: 16, color: colors.textMuted), onPressed: onClear)
          : Icon(LucideIcons.chevronRight300, size: 18, color: disabled ? colors.textDisabled : colors.accent),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final translations = ref.watch(translationsProvider).asData?.value;
    final currency = ref.watch(profileStreamProvider).asData?.value.currency ?? 'EUR';
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(LucideIcons.chevronDown300), onPressed: () => _close()),
        title: Text(_isEdit
            ? (translations?.t('goals.edit') ?? 'Edit goal')
            : (translations?.t('goals.new') ?? 'New goal')),
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
                  Center(child: Text((translations?.t('goals.target') ?? 'Target').toUpperCase(), style: appHeaderStyle(colors))),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openAmountPanel,
                      child: AmountText(amountCents: _targetCents, currency: currency, color: colors.text),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    decoration: InputDecoration(labelText: translations?.t('common.name') ?? 'Name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _sectionLabel(translations?.t('goals.category') ?? 'Savings category'),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    clip: true,
                    padding: EdgeInsets.zero,
                    child: _fieldTile(
                      text: _categoryLabel ?? (translations?.t('goals.select_category') ?? 'Select category'),
                      isPlaceholder: _categoryLabel == null,
                      // Category is locked in edit mode.
                      onTap: _isEdit ? null : _openCategoryPanel,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _sectionLabel(translations?.t('goals.deadline') ?? 'Deadline'),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    clip: true,
                    padding: EdgeInsets.zero,
                    child: _fieldTile(
                      text: _deadline == null
                          ? (translations?.t('goals.no_deadline') ?? 'No deadline')
                          : DateFormat.yMMMd().format(_deadline!),
                      isPlaceholder: _deadline == null,
                      onTap: _openDeadlinePanel,
                      onClear: _deadline == null ? null : () => setState(() => _deadline = null),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_openPanel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: SizedBox(width: double.infinity, child: _saveButton(translations)),
            ),
          BottomActionPanel(
            isOpen: _openPanel != null,
            maxHeight: switch (_openPanel) {
                  'deadline' => 380,
                  _ => 340,
                } +
                MediaQuery.of(context).padding.bottom,
            child: _openPanel == 'amount'
                ? NumericKeypad(
                    amountCents: _targetCents,
                    nextLabel: translations?.t('common.next') ?? 'Next',
                    onKeyTap: () => ref.read(hapticsProvider).selection(),
                    onAmountChanged: (v) => setState(() => _targetCents = v),
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
                child: SizedBox(width: double.infinity, child: _saveButton(translations)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _saveButton(Translations? translations) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: _nameController,
        builder: (context, _, _) => FilledButton(
          onPressed: _canSave ? _save : null,
          child: Text(translations?.t('common.save') ?? 'Save'),
        ),
      );
}

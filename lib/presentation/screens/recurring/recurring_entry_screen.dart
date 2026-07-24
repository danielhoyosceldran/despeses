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
import '../../widgets/simple_picker_sheet.dart';
import '../../widgets/swipe_down_to_close.dart';
import '../../widgets/tag_picker_sheet.dart';

/// Create/edit a recurring-transaction template (feature 3.13). Reuses the
/// transaction entry pattern (keypad + bottom panels), adding a schedule block
/// (frequency + start/end date). Unlike budgets, every field stays editable in
/// edit mode; changing the start date re-anchors the next fire.
class RecurringEntryScreen extends ConsumerStatefulWidget {
  const RecurringEntryScreen({super.key, this.recurring, this.onClose});

  final Recurring? recurring;

  /// Overlay-mode close hook (see the transaction/budget entry screens).
  final void Function(Object? result)? onClose;

  @override
  ConsumerState<RecurringEntryScreen> createState() => _RecurringEntryScreenState();
}

class _RecurringEntryScreenState extends ConsumerState<RecurringEntryScreen> {
  bool get _isEdit => widget.recurring != null;

  String _type = 'expense';
  int _amountCents = 0;
  String _frequency = 'monthly';
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  String? _categoryId;
  String? _paymentMethodId;
  String? _eventId;
  String? _projectId;
  List<String> _tagIds = [];
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final _descriptionFocus = FocusNode();
  final _notesFocus = FocusNode();

  _FieldLabels _labels = const _FieldLabels();

  String? _openPanel;
  Widget? _panelContent;
  GlobalKey<TagPickerContentState>? _tagPickerKey;

  @override
  void initState() {
    super.initState();
    _descriptionFocus.addListener(_dismissPanelOnTextFocus);
    _notesFocus.addListener(_dismissPanelOnTextFocus);
    if (widget.recurring != null) {
      _hydrate(widget.recurring!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAmountPanel());
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _notesController.dispose();
    _descriptionFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  Future<void> _hydrate(Recurring r) async {
    setState(() {
      _type = r.type;
      _amountCents = r.amount;
      _frequency = r.frequency;
      _startDate = r.startDate;
      _endDate = r.endDate;
      _categoryId = r.categoryId;
      _paymentMethodId = r.paymentMethodId;
      _eventId = r.eventId;
      _projectId = r.projectId;
      _descriptionController.text = r.description ?? '';
      _notesController.text = r.notes ?? '';
    });
    final tagIds = await ref.read(recurringRepositoryProvider).tagIdsOf(r.id);
    if (mounted) setState(() => _tagIds = tagIds);
    _refreshLabels();
  }

  Future<void> _refreshLabels() async {
    final labels = await _resolveLabels();
    if (mounted) setState(() => _labels = labels);
  }

  void _closePanel() => setState(() {
        _openPanel = null;
        _panelContent = null;
      });

  void _dismissPanelOnTextFocus() {
    if ((_descriptionFocus.hasFocus || _notesFocus.hasFocus) && _openPanel != null) {
      _closePanel();
    }
  }

  void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  void _openAmountPanel() {
    _dismissKeyboard();
    setState(() {
      _openPanel = 'amount';
      _panelContent = null;
    });
  }

  void _openDatePanel({required bool isEnd}) {
    _dismissKeyboard();
    setState(() {
      _openPanel = isEnd ? 'endDate' : 'startDate';
      _panelContent = CalendarPanel(
        initial: (isEnd ? _endDate : _startDate) ?? DateTime.now(),
        onSelected: (picked) {
          ref.read(hapticsProvider).selection();
          setState(() {
            if (isEnd) {
              _endDate = picked;
            } else {
              _startDate = picked;
            }
          });
          _closePanel();
        },
      );
    });
  }

  Future<void> _openStep(String step) async {
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    _dismissKeyboard();
    switch (step) {
      case 'category':
        setState(() {
          _openPanel = 'category';
          _panelContent = CategoryPickerContent(
            repository: ref.read(categoryRepositoryProvider),
            translations: translations,
            type: _type,
            onSelected: (selected) {
              ref.read(hapticsProvider).selection();
              setState(() => _categoryId = selected.id);
              _refreshLabels();
              _closePanel();
            },
          );
        });
      case 'paymentMethod':
        final methods = await ref.read(referenceDataCacheProvider).paymentMethods();
        if (!mounted) return;
        setState(() {
          _openPanel = 'paymentMethod';
          _panelContent = SimplePickerContent<PaymentMethod>(
            title: translations.t('expenses.payment_method'),
            items: methods,
            labelOf: (m) => displayNameFor(translations, name: m.name, isDefault: m.isDefault),
            onSelected: (selected) {
              ref.read(hapticsProvider).selection();
              setState(() => _paymentMethodId = selected.id);
              _refreshLabels();
              _closePanel();
            },
          );
        });
      case 'tags':
        final groups = await ref.read(referenceDataCacheProvider).tagGroups();
        final tags = await ref.read(referenceDataCacheProvider).tags();
        if (!mounted) return;
        _tagPickerKey = GlobalKey<TagPickerContentState>();
        setState(() {
          _openPanel = 'tags';
          _panelContent = TagPickerContent(
            key: _tagPickerKey,
            groups: groups,
            tags: tags,
            initialSelectedIds: _tagIds,
            translations: translations,
            onDone: (selected) {
              ref.read(hapticsProvider).selection();
              setState(() => _tagIds = selected);
              _closePanel();
            },
          );
        });
      case 'event':
        final events = await ref.read(referenceDataCacheProvider).events();
        if (!mounted) return;
        setState(() {
          _openPanel = 'event';
          _panelContent = SimplePickerContent<Event>(
            title: translations.t('expenses.event'),
            items: events,
            labelOf: (e) => e.name,
            onSelected: (selected) {
              ref.read(hapticsProvider).selection();
              setState(() => _eventId = selected.id);
              _refreshLabels();
              _closePanel();
            },
          );
        });
      case 'project':
        final projects = await ref.read(referenceDataCacheProvider).projects();
        if (!mounted) return;
        setState(() {
          _openPanel = 'project';
          _panelContent = SimplePickerContent<Project>(
            title: translations.t('expenses.project'),
            items: projects,
            labelOf: (p) => p.name,
            onSelected: (selected) {
              ref.read(hapticsProvider).selection();
              setState(() => _projectId = selected.id);
              _refreshLabels();
              _closePanel();
            },
          );
        });
    }
  }

  bool get _canSave =>
      _amountCents > 0 &&
      _descriptionController.text.trim().isNotEmpty &&
      (_endDate == null || !_endDate!.isBefore(_startDate));

  Future<void> _save() async {
    if (!_canSave) return;
    final repo = ref.read(recurringRepositoryProvider);
    final description = _descriptionController.text.trim();
    final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();

    if (_isEdit) {
      await repo.update(
        widget.recurring!.id,
        amountCents: _amountCents,
        type: _type,
        frequency: _frequency,
        startDate: _startDate,
        endDate: _endDate,
        clearEndDate: _endDate == null,
        description: description,
        notes: notes,
        categoryId: _categoryId,
        paymentMethodId: _paymentMethodId,
        eventId: _eventId,
        projectId: _projectId,
        tagIds: _tagIds,
      );
    } else {
      final profile = await ref.read(profileRepositoryProvider).get();
      await repo.create(
        amountCents: _amountCents,
        currency: profile.currency,
        type: _type,
        frequency: _frequency,
        startDate: _startDate,
        endDate: _endDate,
        description: description,
        notes: notes,
        categoryId: _categoryId,
        paymentMethodId: _paymentMethodId,
        eventId: _eventId,
        projectId: _projectId,
        tagIds: _tagIds,
      );
    }
    // Surface any dates already due immediately (start date in the past/today)
    // so the new template's first occurrence appears in the inbox right away.
    await repo.materializeDue();
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

  Color _typeColor(AppSemanticColors semantic) {
    switch (_type) {
      case 'income':
        return semantic.income;
      case 'refund':
        return semantic.refund;
      case 'ahorro':
        return semantic.savings;
      default:
        return semantic.expense;
    }
  }

  Widget _sectionLabel(String text) =>
      Text(text.toUpperCase(), style: appHeaderStyle(context.appColors));

  @override
  Widget build(BuildContext context) {
    final translations = ref.watch(translationsProvider).asData?.value;
    final currency = ref.watch(profileStreamProvider).asData?.value.currency ?? 'EUR';
    final colors = context.appColors;
    final semantic = context.semanticColors;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(icon: const Icon(LucideIcons.chevronDown300), onPressed: () => _close()),
        title: Text(_isEdit
            ? (translations?.t('recurring.edit') ?? 'Edit recurring')
            : (translations?.t('recurring.new') ?? 'New recurring')),
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
                  _buildTypeSelector(translations, colors, semantic),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openAmountPanel,
                      child: AmountText(amountCents: _amountCents, currency: currency, color: _typeColor(semantic)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _descriptionController,
                    focusNode: _descriptionFocus,
                    maxLength: 300,
                    decoration: InputDecoration(
                      labelText: translations?.t('common.description') ?? 'Description',
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Schedule
                  _sectionLabel(translations?.t('recurring.schedule') ?? 'Schedule'),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'monthly', label: Text(translations?.t('recurring.freq_monthly') ?? 'Monthly')),
                      ButtonSegment(value: 'weekly', label: Text(translations?.t('recurring.freq_weekly') ?? 'Weekly')),
                      ButtonSegment(value: 'yearly', label: Text(translations?.t('recurring.freq_yearly') ?? 'Yearly')),
                    ],
                    selected: {_frequency},
                    onSelectionChanged: (s) => setState(() => _frequency = s.first),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    clip: true,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _fieldTile(
                          leading: translations?.t('recurring.starts') ?? 'Starts',
                          text: DateFormat.yMMMd().format(_startDate),
                          isPlaceholder: false,
                          onTap: () => _openDatePanel(isEnd: false),
                        ),
                        Divider(height: 1, color: colors.divider),
                        _fieldTile(
                          leading: translations?.t('recurring.ends') ?? 'Ends',
                          text: _endDate == null
                              ? (translations?.t('recurring.no_end') ?? 'No end date')
                              : DateFormat.yMMMd().format(_endDate!),
                          isPlaceholder: _endDate == null,
                          onTap: () => _openDatePanel(isEnd: true),
                          onClear: _endDate == null ? null : () => setState(() => _endDate = null),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Details
                  _sectionLabel(translations?.t('recurring.details') ?? 'Details'),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    clip: true,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _fieldTile(
                          text: _labels.category ?? (translations?.t('expenses.category') ?? 'Category'),
                          isPlaceholder: _labels.category == null,
                          onTap: () => _openStep('category'),
                        ),
                        Divider(height: 1, color: colors.divider),
                        _fieldTile(
                          text: _labels.paymentMethod ?? (translations?.t('expenses.payment_method') ?? 'Payment method'),
                          isPlaceholder: _labels.paymentMethod == null,
                          onTap: () => _openStep('paymentMethod'),
                        ),
                        Divider(height: 1, color: colors.divider),
                        _fieldTile(
                          text: _tagIds.isEmpty
                              ? (translations?.t('expenses.tags') ?? 'Tags')
                              : (translations?.t('expenses.selected_count').replaceAll('{{count}}', '${_tagIds.length}') ??
                                  '${_tagIds.length} selected'),
                          isPlaceholder: _tagIds.isEmpty,
                          onTap: () => _openStep('tags'),
                        ),
                        Divider(height: 1, color: colors.divider),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _fieldTile(
                                  text: _labels.event ?? (translations?.t('expenses.event') ?? 'Event'),
                                  isPlaceholder: _labels.event == null,
                                  onTap: () => _openStep('event'),
                                ),
                              ),
                              VerticalDivider(width: 1, color: colors.divider),
                              Expanded(
                                child: _fieldTile(
                                  text: _labels.project ?? (translations?.t('expenses.project') ?? 'Project'),
                                  isPlaceholder: _labels.project == null,
                                  onTap: () => _openStep('project'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _notesController,
                    focusNode: _notesFocus,
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: translations?.t('expenses.notes') ?? 'Notes',
                      counterText: '',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_openPanel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: _openPanel == 'tags'
                  ? Row(
                      children: [
                        Expanded(child: _saveButton(translations)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _tagPickerKey?.currentState?.confirm(),
                            child: Text(translations?.t('common.next') ?? 'Next'),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(width: double.infinity, child: _saveButton(translations)),
            ),
          BottomActionPanel(
            isOpen: _openPanel != null,
            maxHeight: switch (_openPanel) {
                  'startDate' || 'endDate' => 380,
                  _ => 340,
                } +
                MediaQuery.of(context).padding.bottom,
            child: _openPanel == 'amount'
                ? NumericKeypad(
                    amountCents: _amountCents,
                    nextLabel: translations?.t('common.next') ?? 'Next',
                    onKeyTap: () => ref.read(hapticsProvider).selection(),
                    onAmountChanged: (v) => setState(() => _amountCents = v),
                    onNext: () {
                      _closePanel();
                      _descriptionFocus.requestFocus();
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

  Widget _saveButton(Translations? translations) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _descriptionController,
      builder: (context, _, _) => FilledButton(
        onPressed: _canSave ? _save : null,
        child: Text(translations?.t('common.save') ?? 'Save'),
      ),
    );
  }

  /// Field row for the detail/schedule cards. Optional [leading] label sits
  /// muted before the value; [onClear] adds a trailing clear button.
  Widget _fieldTile({
    required String text,
    required bool isPlaceholder,
    String? leading,
    VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    final colors = context.appColors;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      title: Row(
        children: [
          if (leading != null) ...[
            Text(leading, style: TextStyle(color: colors.textMuted)),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              text,
              textAlign: leading != null ? TextAlign.end : TextAlign.start,
              style: TextStyle(color: isPlaceholder ? colors.textMuted : colors.text),
            ),
          ),
        ],
      ),
      trailing: onClear != null
          ? IconButton(
              icon: Icon(LucideIcons.x300, size: 16, color: colors.textMuted),
              onPressed: onClear,
            )
          : null,
      onTap: onTap,
    );
  }

  Widget _buildTypeSelector(Translations? translations, AppColors colors, AppSemanticColors semantic) {
    final entries = <(String, String, Color)>[
      ('expense', translations?.t('expenses.type_expense') ?? 'Expense', semantic.expense),
      ('income', translations?.t('expenses.type_income') ?? 'Income', semantic.income),
      ('refund', translations?.t('expenses.type_refund') ?? 'Refund', semantic.refund),
      ('ahorro', translations?.t('expenses.type_ahorro') ?? 'Savings', semantic.savings),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('|', style: TextStyle(color: colors.divider)),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectType(entries[i].$1),
            child: Text(
              entries[i].$2,
              // Always bold so selecting an entry doesn't shift layout/wrap.
              style: TextStyle(
                color: _type == entries[i].$1 ? entries[i].$3 : colors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _selectType(String newType) {
    if (newType == _type) return;
    setState(() {
      _type = newType;
      _categoryId = null; // category trees differ per type
    });
    _refreshLabels();
  }

  Future<_FieldLabels> _resolveLabels() async {
    final translations = await ref.read(translationsProvider.future);
    final cache = ref.read(referenceDataCacheProvider);

    String? categoryLabel;
    if (_categoryId != null) {
      final categories = await cache.categories();
      final byId = {for (final c in categories) c.id: c};
      final chain = <Category>[];
      var current = byId[_categoryId];
      while (current != null) {
        chain.insert(0, current);
        current = current.parentId == null ? null : byId[current.parentId];
      }
      if (chain.isNotEmpty) {
        categoryLabel =
            chain.map((c) => displayNameFor(translations, name: c.name, isDefault: c.isDefault)).join(' > ');
      }
    }

    String? paymentMethodLabel;
    if (_paymentMethodId != null) {
      final match = (await cache.paymentMethods()).where((m) => m.id == _paymentMethodId);
      if (match.isNotEmpty) {
        paymentMethodLabel = displayNameFor(translations, name: match.first.name, isDefault: match.first.isDefault);
      }
    }

    String? eventLabel;
    if (_eventId != null) {
      final match = (await cache.events()).where((e) => e.id == _eventId);
      if (match.isNotEmpty) eventLabel = match.first.name;
    }

    String? projectLabel;
    if (_projectId != null) {
      final match = (await cache.projects()).where((p) => p.id == _projectId);
      if (match.isNotEmpty) projectLabel = match.first.name;
    }

    return _FieldLabels(
      category: categoryLabel,
      paymentMethod: paymentMethodLabel,
      event: eventLabel,
      project: projectLabel,
    );
  }
}

class _FieldLabels {
  const _FieldLabels({this.category, this.paymentMethod, this.event, this.project});

  final String? category;
  final String? paymentMethod;
  final String? event;
  final String? project;
}

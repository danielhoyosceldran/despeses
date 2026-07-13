import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database.dart';
import '../../widgets/bottom_action_panel.dart';
import '../../widgets/category_picker_sheet.dart';
import '../../widgets/numeric_keypad.dart';
import '../../widgets/simple_picker_sheet.dart';
import '../../widgets/tag_picker_sheet.dart';

/// The rich transaction entry flow (plan §3): full-screen, own numeric
/// keypad, field rows opening embedded bottom panels, auto-advancing steps
/// (skipping tags/event/project when the user hasn't created any), category
/// drill-down, fixed save bar.
class ExpenseEntryScreen extends ConsumerStatefulWidget {
  const ExpenseEntryScreen({super.key, this.expenseId});

  /// When set, edits an existing transaction instead of creating a new one.
  final String? expenseId;

  @override
  ConsumerState<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

const _fieldStepOrder = [
  'amount',
  'category',
  'paymentMethod',
  'tags',
  'event',
  'project',
  'description',
  'notes',
];

class _ExpenseEntryScreenState extends ConsumerState<ExpenseEntryScreen> {
  String _type = 'expense';
  int _amountCents = 0;
  DateTime? _date = DateTime.now();
  String? _categoryId;
  String? _paymentMethodId;
  String? _eventId;
  String? _projectId;
  List<String> _tagIds = [];
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final _descriptionFocus = FocusNode();
  final _notesFocus = FocusNode();

  bool _loadingExisting = false;

  /// Which field currently has its panel open, if any.
  String? _openPanel;
  Widget? _panelContent;
  GlobalKey<TagPickerContentState>? _tagPickerKey;

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(() => setState(() {}));
    if (widget.expenseId != null) {
      _loadExisting(widget.expenseId!);
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

  Future<void> _loadExisting(String id) async {
    setState(() => _loadingExisting = true);
    final repo = ref.read(expenseRepositoryProvider);
    final expense = await repo.byId(id);
    if (expense == null) return;
    final tagIds = await repo.tagIdsOf(id);
    setState(() {
      _type = expense.type;
      _amountCents = expense.amount;
      _date = expense.date;
      _categoryId = expense.categoryId;
      _paymentMethodId = expense.paymentMethodId;
      _eventId = expense.eventId;
      _projectId = expense.projectId;
      _tagIds = tagIds;
      _descriptionController.text = expense.description ?? '';
      _notesController.text = expense.notes ?? '';
      _loadingExisting = false;
    });
  }

  void _closePanel() => setState(() {
        _openPanel = null;
        _panelContent = null;
      });

  void _openAmountPanel() {
    setState(() {
      _openPanel = 'amount';
      _panelContent = null;
    });
  }

  void _openDatePanel() {
    setState(() {
      _openPanel = 'date';
      _panelContent = _DatePanel(
        initial: _date ?? DateTime.now(),
        onSelected: (picked) {
          setState(() => _date = picked);
          _closePanel();
        },
      );
    });
  }

  Future<void> _openNextStep(String afterStep) async {
    final cache = ref.read(referenceDataCacheProvider);
    final categories = await cache.categories();
    final paymentMethods = await cache.paymentMethods();
    final tags = await cache.tags();
    final events = await cache.events();
    final projects = await cache.projects();

    final available = <String>{
      'amount',
      'description',
      'notes',
      if (categories.isNotEmpty) 'category',
      if (paymentMethods.isNotEmpty) 'paymentMethod',
      if (tags.isNotEmpty) 'tags',
      if (events.isNotEmpty) 'event',
      if (projects.isNotEmpty) 'project',
    };

    final startIndex = _fieldStepOrder.indexOf(afterStep) + 1;
    for (var i = startIndex; i < _fieldStepOrder.length; i++) {
      final step = _fieldStepOrder[i];
      if (!available.contains(step)) continue;
      if (!mounted) return;
      switch (step) {
        case 'amount':
          _openAmountPanel();
        case 'description':
          _closePanel();
          _descriptionFocus.requestFocus();
        case 'notes':
          _closePanel();
          _notesFocus.requestFocus();
        default:
          await _openStep(step);
      }
      return;
    }
    _closePanel();
  }

  Future<void> _openStep(String step) async {
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    switch (step) {
      case 'category':
        setState(() {
          _openPanel = 'category';
          _panelContent = CategoryPickerContent(
            repository: ref.read(categoryRepositoryProvider),
            translations: translations,
            type: _type,
            onSelected: (selected) {
              setState(() => _categoryId = selected.id);
              _closePanel();
              _openNextStep('category');
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
              setState(() => _paymentMethodId = selected.id);
              _closePanel();
              _openNextStep('paymentMethod');
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
              setState(() => _tagIds = selected);
              _closePanel();
              _openNextStep('tags');
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
              setState(() => _eventId = selected.id);
              _closePanel();
              _openNextStep('event');
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
              setState(() => _projectId = selected.id);
              _closePanel();
              _openNextStep('project');
            },
          );
        });
    }
  }

  bool get _canSave =>
      _amountCents > 0 &&
      _date != null &&
      _categoryId != null &&
      _paymentMethodId != null &&
      _descriptionController.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    final profile = await ref.read(profileRepositoryProvider).get();
    final repo = ref.read(expenseRepositoryProvider);
    if (widget.expenseId == null) {
      await repo.create(
        amountCents: _amountCents,
        currency: profile.currency,
        type: _type,
        date: _date!,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        categoryId: _categoryId,
        paymentMethodId: _paymentMethodId,
        eventId: _eventId,
        projectId: _projectId,
        tagIds: _tagIds,
      );
    } else {
      await repo.update(
        widget.expenseId!,
        amountCents: _amountCents,
        type: _type,
        date: _date!,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        categoryId: _categoryId,
        paymentMethodId: _paymentMethodId,
        eventId: _eventId,
        projectId: _projectId,
        tagIds: _tagIds,
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Color _typeColor(AppColors colors, AppSemanticColors semantic) {
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

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;
    final profileAsync = ref.watch(profileStreamProvider);
    final currency = profileAsync.asData?.value.currency ?? 'EUR';
    final colors = context.appColors;
    final semantic = context.semanticColors;

    if (_loadingExisting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft300),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'expense',
              label: Text(translations?.t('expenses.type_expense') ?? 'Expense', style: TextStyle(color: semantic.expense)),
            ),
            ButtonSegment(
              value: 'income',
              label: Text(translations?.t('expenses.type_income') ?? 'Income', style: TextStyle(color: semantic.income)),
            ),
            ButtonSegment(
              value: 'refund',
              label: Text(translations?.t('expenses.type_refund') ?? 'Refund', style: TextStyle(color: semantic.refund)),
            ),
            ButtonSegment(
              value: 'ahorro',
              label: Text(translations?.t('expenses.type_ahorro') ?? 'Savings', style: TextStyle(color: semantic.savings)),
            ),
          ],
          selected: {_type},
          onSelectionChanged: (selection) => setState(() {
            final newType = selection.first;
            if (newType != _type) {
              _type = newType;
              // Category trees differ per type — the previous selection is invalid.
              _categoryId = null;
            }
          }),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildFieldsView(translations, colors, semantic, currency)),
          if (_openPanel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: _openPanel == 'tags'
                  ? Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _canSave ? _save : null,
                            child: Text(translations?.t('common.save') ?? 'Save'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              _tagPickerKey?.currentState?.confirm();
                            },
                            child: Text(translations?.t('common.next') ?? 'Next'),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _canSave ? _save : null,
                        child: Text(translations?.t('common.save') ?? 'Save'),
                      ),
                    ),
            ),
          BottomActionPanel(
            isOpen: _openPanel != null,
            maxHeight: 4 * 56,
            child: _openPanel == 'amount'
                ? NumericKeypad(
                    amountCents: _amountCents,
                    nextLabel: translations?.t('common.next') ?? 'Next',
                    onAmountChanged: (v) => setState(() => _amountCents = v),
                    onNext: () {
                      _closePanel();
                      _openNextStep('amount');
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
                  child: FilledButton(
                    onPressed: _canSave ? _save : null,
                    child: Text(translations?.t('common.save') ?? 'Save'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFieldsView(
    Translations? translations,
    AppColors colors,
    AppSemanticColors semantic,
    String currency,
  ) {
    return FutureBuilder<_FieldLabels>(
      future: _resolveLabels(),
      builder: (context, snapshot) {
        final labels = snapshot.data;

        return ListView(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListTile(
                      title: Text(_date == null ? (translations?.t('expenses.select') ?? 'Select') : DateFormat.yMMMd().format(_date!)),
                      onTap: _openDatePanel,
                    ),
                  ),
                  VerticalDivider(width: 1, color: colors.divider),
                  Expanded(
                    child: ListTile(
                      title: Text(
                        '${(_amountCents / 100).toStringAsFixed(2)} $currency',
                        style: TextStyle(color: _typeColor(colors, semantic)),
                      ),
                      onTap: _openAmountPanel,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),
            ListTile(
              title: Text(labels?.category ?? (translations?.t('expenses.select') ?? 'Select')),
              onTap: () => _openStep('category'),
            ),
            Divider(height: 1, color: colors.divider),
            ListTile(
              title: Text(labels?.paymentMethod ?? (translations?.t('expenses.select') ?? 'Select')),
              onTap: () => _openStep('paymentMethod'),
            ),
            Divider(height: 1, color: colors.divider),
            ListTile(
              title: Text(
                _tagIds.isEmpty
                    ? (translations?.t('expenses.tags') ?? 'Tags')
                    : (translations?.t('expenses.selected_count').replaceAll('{{count}}', '${_tagIds.length}') ??
                        '${_tagIds.length} selected'),
              ),
              onTap: () => _openStep('tags'),
            ),
            Divider(height: 1, color: colors.divider),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListTile(
                      title: Text(labels?.event ?? (translations?.t('expenses.event') ?? 'Event')),
                      onTap: () => _openStep('event'),
                    ),
                  ),
                  VerticalDivider(width: 1, color: colors.divider),
                  Expanded(
                    child: ListTile(
                      title: Text(labels?.project ?? (translations?.t('expenses.project') ?? 'Project')),
                      onTap: () => _openStep('project'),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.divider),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                controller: _descriptionController,
                focusNode: _descriptionFocus,
                maxLength: 300,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _notesFocus.requestFocus(),
                decoration: InputDecoration(labelText: translations?.t('common.description') ?? 'Description'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: TextField(
                controller: _notesController,
                focusNode: _notesFocus,
                maxLength: 1000,
                maxLines: 3,
                decoration: InputDecoration(labelText: translations?.t('expenses.notes') ?? 'Notes'),
              ),
            ),
          ],
        );
      },
    );
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
        categoryLabel = chain.map((c) => displayNameFor(translations, name: c.name, isDefault: c.isDefault)).join(' > ');
      }
    }

    String? paymentMethodLabel;
    if (_paymentMethodId != null) {
      final methods = await cache.paymentMethods();
      final match = methods.where((m) => m.id == _paymentMethodId);
      if (match.isNotEmpty) {
        paymentMethodLabel = displayNameFor(translations, name: match.first.name, isDefault: match.first.isDefault);
      }
    }

    String? eventLabel;
    if (_eventId != null) {
      final events = await cache.events();
      final match = events.where((e) => e.id == _eventId);
      if (match.isNotEmpty) eventLabel = match.first.name;
    }

    String? projectLabel;
    if (_projectId != null) {
      final projects = await cache.projects();
      final match = projects.where((p) => p.id == _projectId);
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

/// Own calendar panel (plan §3.2): month navigation, today marked, week
/// starts Monday. Replaces the native `showDatePicker`.
class _DatePanel extends StatefulWidget {
  const _DatePanel({required this.initial, required this.onSelected});

  final DateTime initial;
  final ValueChanged<DateTime> onSelected;

  @override
  State<_DatePanel> createState() => _DatePanelState();
}

class _DatePanelState extends State<_DatePanel> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final today = DateTime.now();
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final leadingBlanks = (firstOfMonth.weekday - DateTime.monday) % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.chevronLeft300),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              ),
              Text(DateFormat.yMMMM().format(_month), style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: const Icon(LucideIcons.chevronRight300),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.count(
              crossAxisCount: 7,
              children: [
                for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
                for (var d = 1; d <= daysInMonth; d++)
                  _DayCell(
                    day: d,
                    isToday: today.year == _month.year && today.month == _month.month && today.day == d,
                    onTap: () => widget.onSelected(DateTime(_month.year, _month.month, d)),
                    accent: colors.accent,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.isToday, required this.onTap, required this.accent});

  final int day;
  final bool isToday;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: isToday
              ? BoxDecoration(color: accent.withValues(alpha: 0.15), shape: BoxShape.circle)
              : null,
          child: Text('$day', style: isToday ? TextStyle(color: accent, fontWeight: FontWeight.w600) : null),
        ),
      ),
    );
  }
}

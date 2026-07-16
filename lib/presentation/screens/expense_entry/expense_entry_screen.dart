import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/haptics/haptics.dart';
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

/// The rich transaction entry flow (plan §3): full-screen, own numeric
/// keypad, field rows opening embedded bottom panels, auto-advancing steps
/// (skipping tags/event/project when the user hasn't created any), category
/// drill-down, fixed save bar.
/// Initial values to pre-fill a *new* transaction with — used by the recurring
/// "edit & confirm" flow (feature 3.13), which opens this screen seeded from a
/// pending occurrence so the user can tweak (e.g. the amount of a variable
/// bill) before it becomes a real expense.
class ExpenseSeed {
  const ExpenseSeed({
    required this.type,
    required this.amountCents,
    required this.date,
    this.description,
    this.notes,
    this.categoryId,
    this.paymentMethodId,
    this.eventId,
    this.projectId,
    this.tagIds = const [],
  });

  final String type;
  final int amountCents;
  final DateTime date;
  final String? description;
  final String? notes;
  final String? categoryId;
  final String? paymentMethodId;
  final String? eventId;
  final String? projectId;
  final List<String> tagIds;
}

class ExpenseEntryScreen extends ConsumerStatefulWidget {
  const ExpenseEntryScreen({super.key, this.expenseId, this.seed, this.onClose});

  /// When set, edits an existing transaction instead of creating a new one.
  final String? expenseId;

  /// When set (and [expenseId] is null), pre-fills a new transaction. See
  /// [ExpenseSeed].
  final ExpenseSeed? seed;

  /// Overlay-mode close hook. When null the screen closes via `Navigator.pop`
  /// (it was pushed as a route); when set — e.g. opened as the interactive
  /// drag-up sheet — closing is delegated so the host can animate it away.
  final void Function(Object? result)? onClose;

  @override
  ConsumerState<ExpenseEntryScreen> createState() => _ExpenseEntryScreenState();
}

// Auto-advance chain on "Next": amount → description → category → payment
// method, then stop. Remaining fields (tags, event, project, notes) are filled
// manually by the user.
const _fieldStepOrder = [
  'amount',
  'description',
  'category',
  'paymentMethod',
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

  /// Resolved display labels for the picked category/method/event/project.
  /// Resolved once when a selection changes (not inside `build`) so typing in
  /// the description no longer re-runs the lookup and flickers the tiles (R4).
  _FieldLabels _labels = const _FieldLabels();

  /// Which field currently has its panel open, if any.
  String? _openPanel;
  Widget? _panelContent;
  GlobalKey<TagPickerContentState>? _tagPickerKey;

  @override
  void initState() {
    super.initState();
    // Focusing a text field must dismiss any open bottom panel (keypad/pickers)
    // so the OS keyboard doesn't stack on top of it.
    _descriptionFocus.addListener(_dismissPanelOnTextFocus);
    _notesFocus.addListener(_dismissPanelOnTextFocus);
    if (widget.expenseId != null) {
      _loadExisting(widget.expenseId!);
    } else if (widget.seed != null) {
      _hydrateFromSeed(widget.seed!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAmountPanel());
    }
  }

  /// Pre-fills a new transaction from a [ExpenseSeed] (recurring confirm flow).
  /// Unlike a blank new entry, the keypad does not auto-open — the user is
  /// reviewing already-filled values, not starting from scratch.
  void _hydrateFromSeed(ExpenseSeed seed) {
    _type = seed.type;
    _amountCents = seed.amountCents;
    _date = seed.date;
    _categoryId = seed.categoryId;
    _paymentMethodId = seed.paymentMethodId;
    _eventId = seed.eventId;
    _projectId = seed.projectId;
    _tagIds = List.of(seed.tagIds);
    _descriptionController.text = seed.description ?? '';
    _notesController.text = seed.notes ?? '';
    _refreshLabels();
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
    _refreshLabels();
  }

  /// Recomputes [_labels] off [build]. Call after any dimension selection
  /// changes (category/method/event/project) or after loading an existing row.
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

  /// Opening a bottom panel must drop any text-field focus so the OS keyboard
  /// hides (otherwise it stacks on top of the panel).
  void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  void _openAmountPanel() {
    _dismissKeyboard();
    setState(() {
      _openPanel = 'amount';
      _panelContent = null;
    });
  }

  void _openDatePanel() {
    _dismissKeyboard();
    setState(() {
      _openPanel = 'date';
      _panelContent = CalendarPanel(
        initial: _date ?? DateTime.now(),
        onSelected: (picked) {
          ref.read(hapticsProvider).selection();
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
              ref.read(hapticsProvider).selection();
              setState(() => _paymentMethodId = selected.id);
              _refreshLabels();
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
              ref.read(hapticsProvider).selection();
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
              ref.read(hapticsProvider).selection();
              setState(() => _eventId = selected.id);
              _refreshLabels();
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
              ref.read(hapticsProvider).selection();
              setState(() => _projectId = selected.id);
              _refreshLabels();
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
    _close(true);
  }

  /// Close the screen, routing through [ExpenseEntryScreen.onClose] when hosted
  /// as an overlay sheet, else popping the route.
  void _close([Object? result]) {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose(result);
    } else if (mounted) {
      Navigator.of(context).pop(result);
    }
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
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronDown300),
          onPressed: () => _close(),
        ),
        title: TextButton(
          onPressed: _openDatePanel,
          child: Text(
            _date == null
                ? (translations?.t('expenses.select') ?? 'Select')
                : DateFormat.yMd().format(_date!),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colors.text),
          ),
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
                        Expanded(child: _saveButton(translations)),
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
                  : SizedBox(width: double.infinity, child: _saveButton(translations)),
            ),
          BottomActionPanel(
            isOpen: _openPanel != null,
            maxHeight: switch (_openPanel) {
                  'date' => 380,
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
                child: SizedBox(width: double.infinity, child: _saveButton(translations)),
              ),
            ),
        ],
      ),
    );
  }

  /// Save button whose enabled state tracks the description field directly (via
  /// [ValueListenableBuilder]) instead of rebuilding the whole screen on every
  /// keystroke (R4). Amount/category/method/date already trigger `setState`.
  Widget _saveButton(Translations? translations) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _descriptionController,
      builder: (context, _, _) => FilledButton(
        onPressed: _canSave ? _save : null,
        child: Text(translations?.t('common.save') ?? 'Save'),
      ),
    );
  }

  Widget _buildFieldsView(
    Translations? translations,
    AppColors colors,
    AppSemanticColors semantic,
    String currency,
  ) {
    final labels = _labels;
    return SwipeDownToClose(
          onClose: _close,
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
          children: [
            _buildTypeSelector(translations, colors, semantic),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: GestureDetector(
                onTap: _openAmountPanel,
                behavior: HitTestBehavior.opaque,
                child: AmountText(
                  amountCents: _amountCents,
                  currency: currency,
                  color: _typeColor(colors, semantic),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Description — themed filled input; carries its own surface, no
            // wrapping card (its border would double up with the input's).
            TextField(
              controller: _descriptionController,
              focusNode: _descriptionFocus,
              maxLength: 300,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _openNextStep('description'),
              decoration: InputDecoration(
                labelText: translations?.t('common.description') ?? 'Description',
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              clip: true,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _fieldTile(labels.category ?? (translations?.t('expenses.category') ?? 'Category'), () => _openStep('category')),
                  Divider(height: 1, color: colors.divider),
                  _fieldTile(labels.paymentMethod ?? (translations?.t('expenses.payment_method') ?? 'Payment method'), () => _openStep('paymentMethod')),
                  Divider(height: 1, color: colors.divider),
                  _fieldTile(
                    _tagIds.isEmpty
                        ? (translations?.t('expenses.tags') ?? 'Tags')
                        : (translations?.t('expenses.selected_count').replaceAll('{{count}}', '${_tagIds.length}') ??
                            '${_tagIds.length} selected'),
                    () => _openStep('tags'),
                  ),
                  Divider(height: 1, color: colors.divider),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _fieldTile(labels.event ?? (translations?.t('expenses.event') ?? 'Event'), () => _openStep('event')),
                        ),
                        VerticalDivider(width: 1, color: colors.divider),
                        Expanded(
                          child: _fieldTile(labels.project ?? (translations?.t('expenses.project') ?? 'Project'), () => _openStep('project')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Notes — the themed input carries its own filled surface; no
            // wrapping card (its border would double up with the input's).
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
        );
  }

  /// Compact tappable field row for the entry card (tighter padding than a
  /// default `ListTile`).
  Widget _fieldTile(String text, VoidCallback onTap) => ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        title: Text(text),
        onTap: onTap,
      );

  /// Horizontal "Expense | Income | Refund | Savings" text selector (ref
  /// layout): tap sets the type; selected label takes its semantic colour and
  /// bold weight, the rest are muted.
  Widget _buildTypeSelector(Translations? translations, AppColors colors, AppSemanticColors semantic) {
    final entries = <(String, String, Color)>[
      ('expense', translations?.t('expenses.type_expense') ?? 'Expense', semantic.expense),
      ('income', translations?.t('expenses.type_income') ?? 'Income', semantic.income),
      ('refund', translations?.t('expenses.type_refund') ?? 'Refund', semantic.refund),
      ('ahorro', translations?.t('expenses.type_ahorro') ?? 'Savings', semantic.savings),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
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
              style: TextStyle(
                color: _type == entries[i].$1 ? entries[i].$3 : colors.textMuted,
                fontWeight: _type == entries[i].$1 ? FontWeight.w600 : FontWeight.w400,
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
      // Category trees differ per type — the previous selection is invalid.
      _categoryId = null;
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

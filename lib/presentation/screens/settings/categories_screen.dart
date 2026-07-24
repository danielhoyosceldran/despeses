import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database.dart';
import '../../../domain/repositories/errors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entity_form_dialog.dart';
import '../../widgets/entity_list_tile.dart';
import '../../widgets/page_title_header.dart';

/// Drill-down category manager (max 3 levels, plan §3.7): breadcrumb at the
/// top, reorderable list of the current level's children.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  final List<Category> _breadcrumb = [];
  List<Category> _children = [];
  bool _loading = true;
  bool _selectionMode = false;
  final Set<String> _selected = {};

  /// Which transaction-type category forest is being managed. Only switchable
  /// at the root level.
  String _type = 'expense';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _currentParentId => _breadcrumb.isEmpty ? null : _breadcrumb.last.id;

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = ref.read(categoryRepositoryProvider);
    final children = await repo.listChildren(_currentParentId, type: _type);
    setState(() {
      _children = children;
      _loading = false;
    });
  }

  void _switchType(String type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _breadcrumb.clear();
    });
    _load();
  }

  Future<void> _create() async {
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    final result = await showEntityFormDialog(
      context,
      title: translations.t('categories.new'),
      translations: translations,
    );
    if (result == null) return;
    try {
      await ref.read(categoryRepositoryProvider).create(
            name: result.name,
            parentId: _currentParentId,
            type: _type,
            color: result.color,
            icon: result.icon,
          );
    } on DuplicateNameException catch (e) {
      if (mounted) showDuplicateNameToast(context, translations, e.name);
      return;
    }
    ref.read(referenceDataCacheProvider).invalidate();
    ref.invalidate(categoriesListProvider);
    _load();
  }

  Future<void> _edit(Category category) async {
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    final currentName = displayNameFor(translations, name: category.name, isDefault: category.isDefault);
    final result = await showEntityFormDialog(
      context,
      title: translations.t('categories.edit'),
      translations: translations,
      initialName: currentName,
      initialColor: category.color,
      initialIcon: category.icon,
    );
    if (result == null) return;
    final repo = ref.read(categoryRepositoryProvider);
    try {
      if (result.name != currentName) await repo.rename(category.id, result.name);
    } on DuplicateNameException catch (e) {
      if (mounted) showDuplicateNameToast(context, translations, e.name);
      return;
    }
    await repo.updateAppearance(category.id, color: result.color, icon: result.icon);
    ref.read(referenceDataCacheProvider).invalidate();
    ref.invalidate(categoriesListProvider);
    _load();
  }

  Future<bool> _confirmDeleteSelected(List<Category> categories) async {
    final repo = ref.read(categoryRepositoryProvider);
    var budgetCount = 0;
    for (final category in categories) {
      budgetCount += await repo.budgetCount(category.id);
    }
    if (!mounted) return false;
    final translations = ref.read(translationsProvider).asData?.value;
    final message = budgetCount > 0
        ? (translations?.t('categories.delete_with_budgets_multi') ??
                'Selected categories (and their subcategories) have {{count}} budget(s) that will also be deleted. Continue?')
            .replaceAll('{{count}}', '$budgetCount')
        : (translations?.t('common.delete_selected') ?? 'Delete {{count}} selected item(s)?')
            .replaceAll('{{count}}', '${categories.length}');
    return showConfirmDialog(
      context,
      title: translations?.t('categories.delete_title') ?? 'Delete category',
      message: message,
      destructive: true,
    );
  }

  Future<void> _delete(Category category) async {
    final index = _children.indexOf(category);
    setState(() => _children.remove(category));
    try {
      await ref.read(categoryRepositoryProvider).delete(category.id);
      ref.read(referenceDataCacheProvider).invalidate();
      ref.invalidate(categoriesListProvider);
    } catch (_) {
      if (index >= 0) setState(() => _children.insert(index, category));
      if (mounted) {
        final translations = ref.read(translationsProvider).asData?.value;
        showAppToast(
          context,
          (translations?.t('common.error_delete_named') ?? 'Could not delete "{{name}}"')
              .replaceAll('{{name}}', category.name),
          variant: ToastVariant.error,
        );
      }
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = List<Category>.from(_children);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    setState(() => _children = reordered);
    await ref
        .read(categoryRepositoryProvider)
        .reorder(_currentParentId, reordered.map((c) => c.id).toList());
    ref.read(referenceDataCacheProvider).invalidate();
    ref.invalidate(categoriesListProvider);
  }

  void _enterSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _setSelected(String id, bool value) {
    setState(() {
      if (value) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final toDelete = _children.where((c) => _selected.contains(c.id)).toList();
    if (!await _confirmDeleteSelected(toDelete)) return;
    for (final category in toDelete) {
      await _delete(category);
    }
    _exitSelection();
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(LucideIcons.trash2300),
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                ),
                TextButton(
                  onPressed: _exitSelection,
                  child: Text(translations?.t('common.done') ?? 'Done'),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          if (_breadcrumb.isEmpty) ...[
            PageTitleHeader(translations?.t('settings_nav.categories') ?? 'Categories'),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'expense', label: Text(translations?.t('expenses.type_expense') ?? 'Expense')),
                    ButtonSegment(value: 'income', label: Text(translations?.t('expenses.type_income') ?? 'Income')),
                    ButtonSegment(value: 'refund', label: Text(translations?.t('expenses.type_refund') ?? 'Refund')),
                    ButtonSegment(value: 'ahorro', label: Text(translations?.t('expenses.type_ahorro') ?? 'Savings')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => _switchType(s.first),
                ),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.arrowLeft300, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: context.appColors.surfaceAlt,
                      foregroundColor: context.appColors.text,
                      shape: const CircleBorder(),
                    ),
                    onPressed: () {
                      setState(() => _breadcrumb.removeLast());
                      _load();
                    },
                  ),
                  const SizedBox(width: AppSpacing.smMd),
                  Expanded(
                    child: Text(
                      _breadcrumb
                          .map((c) => translations == null
                              ? c.name
                              : displayNameFor(translations, name: c.name, isDefault: c.isDefault))
                          .join('  ›  '),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _children.isEmpty
                    ? EmptyState(translations?.t('categories.empty') ?? 'No categories yet.')
                    : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    buildDefaultDragHandles: false,
                    itemCount: _children.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                      final category = _children[index];
                      final label = translations == null
                          ? category.name
                          : displayNameFor(translations, name: category.name, isDefault: category.isDefault);
                      return EntityListTile(
                        key: ValueKey(category.id),
                        id: category.id,
                        title: label,
                        leadingColor: category.color == null ? null : hexToColor(category.color),
                        icon: category.icon,
                        onEdit: () => _edit(category),
                        onTap: () {
                          setState(() => _breadcrumb.add(category));
                          _load();
                        },
                        onLongPress: () => _enterSelection(category.id),
                        selectionMode: _selectionMode,
                        selected: _selected.contains(category.id),
                        onSelectedChanged: (v) => _setSelected(category.id, v),
                        reorderIndex: index,
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _breadcrumb.length >= 3
          ? null
          : FloatingActionButton(onPressed: _create, child: const Icon(LucideIcons.plus300)),
    );
  }
}

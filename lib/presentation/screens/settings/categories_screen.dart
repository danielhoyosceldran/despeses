import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database.dart';
import '../../widgets/confirm_dialog.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _currentParentId => _breadcrumb.isEmpty ? null : _breadcrumb.last.id;

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = ref.read(categoryRepositoryProvider);
    final children = await repo.listChildren(_currentParentId);
    setState(() {
      _children = children;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final result = await showEntityFormDialog(context, title: 'New category');
    if (result == null) return;
    await ref.read(categoryRepositoryProvider).create(
          name: result.name,
          parentId: _currentParentId,
          color: result.color,
          icon: result.icon,
        );
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<void> _edit(Category category) async {
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    final currentName = displayNameFor(translations, name: category.name, isDefault: category.isDefault);
    final result = await showEntityFormDialog(
      context,
      title: 'Edit category',
      initialName: currentName,
      initialColor: category.color,
      initialIcon: category.icon,
    );
    if (result == null) return;
    final repo = ref.read(categoryRepositoryProvider);
    if (result.name != currentName) await repo.rename(category.id, result.name);
    await repo.updateAppearance(category.id, color: result.color, icon: result.icon);
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<bool> _confirmDelete(Category category, String label) async {
    final budgetCount = await ref.read(categoryRepositoryProvider).budgetCount(category.id);
    if (!mounted) return false;
    final message = budgetCount > 0
        ? '"$label" (and its subcategories) has $budgetCount budget(s) that will also be deleted. Continue?'
        : 'Delete "$label"?';
    return showConfirmDialog(
      context,
      title: 'Delete category',
      message: message,
      destructive: true,
    );
  }

  Future<void> _delete(Category category) async {
    setState(() => _children.remove(category));
    await ref.read(categoryRepositoryProvider).delete(category.id);
    ref.read(referenceDataCacheProvider).invalidate();
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
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(),
      body: Column(
        children: [
          if (_breadcrumb.isEmpty)
            PageTitleHeader(translations?.t('settings_nav.categories') ?? 'Categories')
          else
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
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(category.id),
                        index: index,
                        child: EntityListTile(
                        id: category.id,
                        title: label,
                        leadingColor: category.color == null ? null : hexToColor(category.color),
                        icon: category.icon,
                        onEdit: () => _edit(category),
                        confirmDelete: () => _confirmDelete(category, label),
                        onDeleted: () => _delete(category),
                        onTap: () {
                          setState(() => _breadcrumb.add(category));
                          _load();
                        },
                        ),
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

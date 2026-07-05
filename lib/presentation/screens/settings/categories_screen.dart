import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/entity_form_dialog.dart';

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

  Future<void> _delete(Category category) async {
    final repo = ref.read(categoryRepositoryProvider);
    final budgetCount = await repo.budgetCount(category.id);
    if (!mounted) return;
    final message = budgetCount > 0
        ? 'This category (and its subcategories) has $budgetCount budget(s) that will also be deleted. Continue?'
        : 'Delete this category?';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete category',
      message: message,
      destructive: true,
    );
    if (!confirmed) return;
    await repo.delete(category.id);
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
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
      appBar: AppBar(
        title: Text(translations?.t('settings_nav.categories') ?? 'Categories'),
      ),
      body: Column(
        children: [
          if (_breadcrumb.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.arrowLeft300),
                    onPressed: () {
                      setState(() => _breadcrumb.removeLast());
                      _load();
                    },
                  ),
                  Expanded(
                    child: Text(
                      _breadcrumb
                          .map((c) => translations == null
                              ? c.name
                              : displayNameFor(translations, name: c.name, isDefault: c.isDefault))
                          .join(' > '),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ReorderableListView.builder(
                    itemCount: _children.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                      final category = _children[index];
                      final label = translations == null
                          ? category.name
                          : displayNameFor(translations, name: category.name, isDefault: category.isDefault);
                      return ListTile(
                        key: ValueKey(category.id),
                        leading: category.color == null
                            ? null
                            : CircleAvatar(backgroundColor: hexToColor(category.color), radius: 8),
                        title: Text(label),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(LucideIcons.pencil300), onPressed: () => _edit(category)),
                            IconButton(icon: const Icon(LucideIcons.trash2300), onPressed: () => _delete(category)),
                          ],
                        ),
                        onTap: () {
                          setState(() => _breadcrumb.add(category));
                          _load();
                        },
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

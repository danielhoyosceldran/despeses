import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/entity_form_dialog.dart';
import '../../widgets/entity_list_tile.dart';
import '../../widgets/page_title_header.dart';

class TagsScreen extends ConsumerStatefulWidget {
  const TagsScreen({super.key});

  @override
  ConsumerState<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends ConsumerState<TagsScreen> {
  List<TagGroup> _groups = [];
  Map<String, List<Tag>> _tagsByGroup = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final groupRepo = ref.read(tagGroupRepositoryProvider);
    final tagRepo = ref.read(tagRepositoryProvider);
    final groups = await groupRepo.listAll();
    final byGroup = <String, List<Tag>>{};
    for (final group in groups) {
      byGroup[group.id] = await tagRepo.listByGroup(group.id);
    }
    setState(() {
      _groups = groups;
      _tagsByGroup = byGroup;
      _loading = false;
    });
  }

  Future<void> _create(String groupId) async {
    final result = await showEntityFormDialog(context, title: 'New tag');
    if (result == null) return;
    await ref.read(tagRepositoryProvider).create(
          name: result.name,
          tagGroupId: groupId,
          color: result.color,
          icon: result.icon,
        );
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<void> _edit(Tag tag, String currentName) async {
    final result = await showEntityFormDialog(
      context,
      title: 'Edit tag',
      initialName: currentName,
      initialColor: tag.color,
      initialIcon: tag.icon,
    );
    if (result == null) return;
    final repo = ref.read(tagRepositoryProvider);
    if (result.name != currentName) await repo.rename(tag.id, result.name);
    await repo.updateAppearance(tag.id, color: result.color, icon: result.icon);
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<bool> _confirmDelete(Tag tag, String label) async {
    final budgetCount = await ref.read(tagRepositoryProvider).budgetCount(tag.id);
    if (!mounted) return false;
    final translations = ref.read(translationsProvider).asData?.value;
    final message = budgetCount > 0
        ? (translations?.t('common.delete_with_budgets') ??
                '"{{name}}" has {{count}} budget(s) that will also be deleted. Continue?')
            .replaceAll('{{name}}', label)
            .replaceAll('{{count}}', '$budgetCount')
        : (translations?.t('common.delete_named') ?? 'Delete "{{name}}"?').replaceAll('{{name}}', label);
    return showConfirmDialog(
      context,
      title: translations?.t('tags.delete_title') ?? 'Delete tag',
      message: message,
      destructive: true,
    );
  }

  Future<void> _delete(Tag tag) async {
    final list = _tagsByGroup[tag.tagGroupId];
    final index = list?.indexOf(tag) ?? -1;
    setState(() => list?.remove(tag));
    try {
      await ref.read(tagRepositoryProvider).delete(tag.id);
      ref.read(referenceDataCacheProvider).invalidate();
    } catch (_) {
      if (index >= 0) setState(() => list?.insert(index, tag));
      if (mounted) {
        final translations = ref.read(translationsProvider).asData?.value;
        showAppToast(
          context,
          (translations?.t('common.error_delete_named') ?? 'Could not delete "{{name}}"')
              .replaceAll('{{name}}', tag.name),
          variant: ToastVariant.error,
        );
      }
    }
  }

  Future<void> _reorder(String groupId, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = List<Tag>.from(_tagsByGroup[groupId]!);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    setState(() => _tagsByGroup[groupId] = reordered);
    await ref.read(tagRepositoryProvider).reorder(groupId, reordered.map((t) => t.id).toList());
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
          PageTitleHeader(translations?.t('settings_nav.tags') ?? 'Tags'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    children: [
                      for (final group in _groups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  translations == null
                                      ? group.name
                                      : tagGroupDisplayName(translations, group.name),
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(LucideIcons.plus300, size: 20),
                                onPressed: () => _create(group.id),
                              ),
                            ],
                          ),
                        ),
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: _tagsByGroup[group.id]?.length ?? 0,
                          onReorder: (oldIndex, newIndex) => _reorder(group.id, oldIndex, newIndex),
                          itemBuilder: (context, index) {
                            final tag = _tagsByGroup[group.id]![index];
                            final label = translations == null
                                ? tag.name
                                : displayNameFor(translations, name: tag.name, isDefault: tag.isDefault);
                            return ReorderableDelayedDragStartListener(
                              key: ValueKey(tag.id),
                              index: index,
                              child: EntityListTile(
                                id: tag.id,
                                title: label,
                                leadingColor: tag.color == null ? null : hexToColor(tag.color),
                                icon: tag.icon,
                                onEdit: () => _edit(tag, label),
                                confirmDelete: () => _confirmDelete(tag, label),
                                onDeleted: () => _delete(tag),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

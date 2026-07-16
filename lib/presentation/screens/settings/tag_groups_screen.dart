import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../../domain/repositories/tag_repository.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/entity_form_dialog.dart';
import '../../widgets/entity_list_tile.dart';
import '../../widgets/page_title_header.dart';

class TagGroupsScreen extends ConsumerStatefulWidget {
  const TagGroupsScreen({super.key});

  @override
  ConsumerState<TagGroupsScreen> createState() => _TagGroupsScreenState();
}

class _TagGroupsScreenState extends ConsumerState<TagGroupsScreen> {
  List<TagGroup> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final groups = await ref.read(tagGroupRepositoryProvider).listAll();
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final result = await showEntityFormDialog(
      context,
      title: 'New tag group',
      withColor: false,
      withIcon: false,
    );
    if (result == null) return;
    await ref.read(tagGroupRepositoryProvider).create(result.name);
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<void> _rename(TagGroup group, String currentName) async {
    final result = await showEntityFormDialog(
      context,
      title: 'Rename tag group',
      initialName: currentName,
      withColor: false,
      withIcon: false,
    );
    if (result == null) return;
    await ref.read(tagGroupRepositoryProvider).rename(group.id, result.name);
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<bool> _confirmDelete(String label) {
    final translations = ref.read(translationsProvider).asData?.value;
    return showConfirmDialog(
      context,
      title: translations?.t('tag_groups.delete_title') ?? 'Delete tag group',
      message: (translations?.t('tag_groups.delete_message') ??
              'Its tags will be moved to "Ungrouped" first, then "{{name}}" is deleted.')
          .replaceAll('{{name}}', label),
      destructive: true,
    );
  }

  Future<void> _delete(TagGroup group) async {
    final index = _groups.indexOf(group);
    setState(() => _groups.remove(group));
    try {
      // Throws StateError for the reserved "ungrouped" group — treat like any
      // failure: restore the row and tell the user, don't swallow it (X2).
      await ref.read(tagGroupRepositoryProvider).delete(group.id);
      ref.read(referenceDataCacheProvider).invalidate();
    } catch (_) {
      if (index >= 0) setState(() => _groups.insert(index, group));
      if (mounted) {
        final translations = ref.read(translationsProvider).asData?.value;
        showAppToast(
          context,
          (translations?.t('common.error_delete_named') ?? 'Could not delete "{{name}}"')
              .replaceAll('{{name}}', group.name),
          variant: ToastVariant.error,
        );
      }
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = List<TagGroup>.from(_groups);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    setState(() => _groups = reordered);
    await ref.read(tagGroupRepositoryProvider).reorder(reordered.map((g) => g.id).toList());
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
          PageTitleHeader(translations?.t('settings_nav.tag_groups') ?? 'Tag groups'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    buildDefaultDragHandles: false,
                    itemCount: _groups.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                final group = _groups[index];
                final isUngrouped = group.name == ungroupedKey;
                final label = translations == null
                    ? group.name
                    : tagGroupDisplayName(translations, group.name);
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(group.id),
                  index: index,
                  child: EntityListTile(
                    id: group.id,
                    title: label,
                    onEdit: isUngrouped ? null : () => _rename(group, label),
                    confirmDelete: isUngrouped ? null : () => _confirmDelete(label),
                    onDeleted: () => _delete(group),
                  ),
                );
              },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(LucideIcons.plus300)),
    );
  }
}

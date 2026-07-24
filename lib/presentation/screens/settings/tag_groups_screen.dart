import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../../domain/repositories/errors.dart';
import '../../../domain/repositories/tag_repository.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
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
  bool _selectionMode = false;
  final Set<String> _selected = {};

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
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    final result = await showEntityFormDialog(
      context,
      title: translations.t('tag_groups.new'),
      translations: translations,
      withColor: false,
      withIcon: false,
    );
    if (result == null) return;
    try {
      await ref.read(tagGroupRepositoryProvider).create(result.name);
    } on DuplicateNameException catch (e) {
      if (mounted) showDuplicateNameToast(context, translations, e.name);
      return;
    }
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<void> _rename(TagGroup group, String currentName) async {
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    final result = await showEntityFormDialog(
      context,
      title: translations.t('tag_groups.rename'),
      translations: translations,
      initialName: currentName,
      withColor: false,
      withIcon: false,
    );
    if (result == null) return;
    try {
      await ref.read(tagGroupRepositoryProvider).rename(group.id, result.name);
    } on DuplicateNameException catch (e) {
      if (mounted) showDuplicateNameToast(context, translations, e.name);
      return;
    }
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
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
    final toDelete = _groups.where((g) => _selected.contains(g.id)).toList();
    final translations = ref.read(translationsProvider).asData?.value;
    final confirmed = await showConfirmDialog(
      context,
      title: translations?.t('tag_groups.delete_title') ?? 'Delete tag group',
      message: (translations?.t('common.delete_selected') ?? 'Delete {{count}} selected item(s)?')
          .replaceAll('{{count}}', '${toDelete.length}'),
      destructive: true,
    );
    if (!confirmed) return;
    for (final group in toDelete) {
      await _delete(group);
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
          PageTitleHeader(translations?.t('settings_nav.tag_groups') ?? 'Tag groups'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _groups.isEmpty
                    ? EmptyState(translations?.t('tag_groups.empty') ?? 'No tag groups yet.')
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
                return EntityListTile(
                  key: ValueKey(group.id),
                  id: group.id,
                  title: label,
                  onEdit: isUngrouped ? null : () => _rename(group, label),
                  onLongPress: isUngrouped ? null : () => _enterSelection(group.id),
                  selectionMode: _selectionMode,
                  selected: _selected.contains(group.id),
                  onSelectedChanged: isUngrouped ? null : (v) => _setSelected(group.id, v),
                  reorderIndex: index,
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

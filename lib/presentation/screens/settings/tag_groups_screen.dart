import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../../domain/repositories/tag_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/entity_form_dialog.dart';

class TagGroupsScreen extends ConsumerStatefulWidget {
  const TagGroupsScreen({super.key});

  @override
  ConsumerState<TagGroupsScreen> createState() => _TagGroupsScreenState();
}

class _TagGroupsScreenState extends ConsumerState<TagGroupsScreen> {
  List<TagGroup> _groups = [];
  bool _loading = true;
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _toggleSelection(TagGroup group) {
    if (group.name == ungroupedKey) return;
    setState(() {
      if (_selectedIds.contains(group.id)) {
        _selectedIds.remove(group.id);
      } else {
        _selectedIds.add(group.id);
      }
    });
  }

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

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete tag groups',
      message: 'Their tags will be moved to "Ungrouped" first, then these $count group(s) are deleted.',
      destructive: true,
    );
    if (!confirmed) return;
    final repo = ref.read(tagGroupRepositoryProvider);
    for (final id in _selectedIds) {
      try {
        await repo.delete(id);
      } on StateError catch (_) {}
    }
    setState(() => _selectedIds.clear());
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
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
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : Text(translations?.t('settings_nav.tag_groups') ?? 'Tag groups'),
        leading: _selectionMode
            ? IconButton(icon: const Icon(LucideIcons.x300), onPressed: () => setState(() => _selectedIds.clear()))
            : null,
        actions: _selectionMode
            ? [IconButton(icon: const Icon(LucideIcons.trash2300), onPressed: _deleteSelected)]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
              itemCount: _groups.length,
              onReorder: _reorder,
              itemBuilder: (context, index) {
                final group = _groups[index];
                final isUngrouped = group.name == ungroupedKey;
                final selected = _selectedIds.contains(group.id);
                final label = translations == null
                    ? group.name
                    : tagGroupDisplayName(translations, group.name);
                return ListTile(
                  key: ValueKey(group.id),
                  selected: selected,
                  leading: _selectionMode
                      ? Checkbox(value: selected, onChanged: isUngrouped ? null : (_) => _toggleSelection(group))
                      : null,
                  title: Text(label),
                  trailing: isUngrouped || _selectionMode
                      ? null
                      : IconButton(
                          icon: const Icon(LucideIcons.pencil300),
                          onPressed: () => _rename(group, label),
                        ),
                  onLongPress: () => _toggleSelection(group),
                  onTap: _selectionMode ? () => _toggleSelection(group) : null,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(LucideIcons.plus300)),
    );
  }
}

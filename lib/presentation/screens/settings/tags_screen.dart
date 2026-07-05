import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/entity_form_dialog.dart';

class TagsScreen extends ConsumerStatefulWidget {
  const TagsScreen({super.key});

  @override
  ConsumerState<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends ConsumerState<TagsScreen> {
  List<TagGroup> _groups = [];
  Map<String, List<Tag>> _tagsByGroup = {};
  bool _loading = true;
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _toggleSelection(Tag tag) {
    if (tag.isDefault) return;
    setState(() {
      if (_selectedIds.contains(tag.id)) {
        _selectedIds.remove(tag.id);
      } else {
        _selectedIds.add(tag.id);
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

  Future<void> _deleteSelected() async {
    final repo = ref.read(tagRepositoryProvider);
    var budgetCount = 0;
    for (final id in _selectedIds) {
      budgetCount += await repo.budgetCount(id);
    }
    if (!mounted) return;
    final count = _selectedIds.length;
    final message = budgetCount > 0
        ? 'These $count tags have $budgetCount budget(s) that will also be deleted. Continue?'
        : 'Delete $count selected tag${count == 1 ? '' : 's'}?';
    final confirmed = await showConfirmDialog(context, title: 'Delete tags', message: message, destructive: true);
    if (!confirmed) return;
    for (final id in _selectedIds) {
      await repo.delete(id);
    }
    setState(() => _selectedIds.clear());
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
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
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : Text(translations?.t('settings_nav.tags') ?? 'Tags'),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(LucideIcons.x300),
                onPressed: () => setState(() => _selectedIds.clear()),
              )
            : null,
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(LucideIcons.trash2300),
                  onPressed: _deleteSelected,
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                for (final group in _groups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  translations == null
                                      ? group.name
                                      : tagGroupDisplayName(translations, group.name),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
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
                          itemCount: _tagsByGroup[group.id]?.length ?? 0,
                          onReorder: (oldIndex, newIndex) => _reorder(group.id, oldIndex, newIndex),
                          itemBuilder: (context, index) {
                            final tag = _tagsByGroup[group.id]![index];
                            final label = translations == null
                                ? tag.name
                                : displayNameFor(translations, name: tag.name, isDefault: tag.isDefault);
                            final selected = _selectedIds.contains(tag.id);
                            return ListTile(
                              key: ValueKey(tag.id),
                              selected: selected,
                              leading: _selectionMode
                                  ? Checkbox(
                                      value: selected,
                                      onChanged: tag.isDefault ? null : (_) => _toggleSelection(tag),
                                    )
                                  : tag.color == null
                                      ? null
                                      : CircleAvatar(backgroundColor: hexToColor(tag.color), radius: 8),
                              title: Text(label),
                              trailing: _selectionMode
                                  ? null
                                  : IconButton(icon: const Icon(LucideIcons.pencil300), onPressed: () => _edit(tag, label)),
                              onLongPress: () => _toggleSelection(tag),
                              onTap: _selectionMode ? () => _toggleSelection(tag) : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

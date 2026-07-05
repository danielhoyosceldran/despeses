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

  Future<void> _delete(TagGroup group) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete tag group',
      message: 'Its tags will be moved to "Ungrouped" first, then this group is deleted.',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(tagGroupRepositoryProvider).delete(group.id);
      ref.read(referenceDataCacheProvider).invalidate();
      _load();
    } on StateError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
      appBar: AppBar(title: Text(translations?.t('settings_nav.tag_groups') ?? 'Tag groups')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
              itemCount: _groups.length,
              onReorder: _reorder,
              itemBuilder: (context, index) {
                final group = _groups[index];
                final isUngrouped = group.name == ungroupedKey;
                final label = translations == null
                    ? group.name
                    : tagGroupDisplayName(translations, group.name);
                return ListTile(
                  key: ValueKey(group.id),
                  title: Text(label),
                  trailing: isUngrouped
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _rename(group, label),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(group),
                            ),
                          ],
                        ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(Icons.add)),
    );
  }
}

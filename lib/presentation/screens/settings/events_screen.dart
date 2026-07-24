import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../../domain/repositories/errors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entity_list_tile.dart';
import '../../widgets/event_project_form_dialog.dart';
import '../../widgets/page_title_header.dart';

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  List<Event> _events = [];
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
    final events = await ref.read(eventRepositoryProvider).listAll();
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    final result = await showEventProjectFormDialog(
      context,
      title: translations.t('events.new'),
      translations: translations,
    );
    if (result == null) return;
    try {
      await ref.read(eventRepositoryProvider).create(
            name: result.name,
            description: result.description,
            startsAt: result.startsAt,
            endsAt: result.endsAt,
          );
    } on DuplicateNameException catch (e) {
      if (mounted) showDuplicateNameToast(context, translations, e.name);
      return;
    }
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<void> _edit(Event event) async {
    final translations = await ref.read(translationsProvider.future);
    if (!mounted) return;
    final result = await showEventProjectFormDialog(
      context,
      title: translations.t('events.edit'),
      translations: translations,
      initialName: event.name,
      initialDescription: event.description,
      initialStartsAt: event.startsAt,
      initialEndsAt: event.endsAt,
    );
    if (result == null) return;
    try {
      await ref.read(eventRepositoryProvider).update(
            event.id,
            name: result.name,
            description: result.description,
            startsAt: result.startsAt,
            endsAt: result.endsAt,
          );
    } on DuplicateNameException catch (e) {
      if (mounted) showDuplicateNameToast(context, translations, e.name);
      return;
    }
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<bool> _confirmDeleteSelected(List<Event> events) async {
    final repo = ref.read(eventRepositoryProvider);
    var budgetCount = 0;
    for (final event in events) {
      budgetCount += await repo.budgetCount(event.id);
    }
    if (!mounted) return false;
    final translations = ref.read(translationsProvider).asData?.value;
    final message = budgetCount > 0
        ? (translations?.t('common.delete_with_budgets_multi') ??
                'Selected events have {{count}} budget(s) that will also be deleted. Continue?')
            .replaceAll('{{count}}', '$budgetCount')
        : (translations?.t('common.delete_selected') ?? 'Delete {{count}} selected item(s)?')
            .replaceAll('{{count}}', '${events.length}');
    return showConfirmDialog(
      context,
      title: translations?.t('events.delete_title') ?? 'Delete event',
      message: message,
      destructive: true,
    );
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
    final toDelete = _events.where((e) => _selected.contains(e.id)).toList();
    if (!await _confirmDeleteSelected(toDelete)) return;
    for (final event in toDelete) {
      await _delete(event);
    }
    _exitSelection();
  }

  Future<void> _delete(Event event) async {
    final index = _events.indexOf(event);
    setState(() => _events.remove(event));
    try {
      await ref.read(eventRepositoryProvider).delete(event.id);
      ref.read(referenceDataCacheProvider).invalidate();
    } catch (_) {
      // Delete failed — undo the optimistic removal so the row doesn't vanish
      // from the UI while still living in the DB (X2).
      if (index >= 0) setState(() => _events.insert(index, event));
      if (mounted) {
        final translations = ref.read(translationsProvider).asData?.value;
        showAppToast(
          context,
          (translations?.t('common.error_delete_named') ?? 'Could not delete "{{name}}"')
              .replaceAll('{{name}}', event.name),
          variant: ToastVariant.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final translations = ref.watch(translationsProvider).asData?.value;
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
          PageTitleHeader(translations?.t('settings_nav.events') ?? 'Events'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _events.isEmpty
                    ? EmptyState(translations?.t('events.empty') ?? 'No events yet.')
                    : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      return EntityListTile(
                        key: ValueKey(event.id),
                        id: event.id,
                        title: event.name,
                        subtitle: event.description,
                        onEdit: () => _edit(event),
                        onLongPress: () => _enterSelection(event.id),
                        selectionMode: _selectionMode,
                        selected: _selected.contains(event.id),
                        onSelectedChanged: (v) => _setSelected(event.id, v),
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

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/event_project_form_dialog.dart';

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  List<Event> _events = [];
  bool _loading = true;
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _toggleSelection(Event event) {
    setState(() {
      if (_selectedIds.contains(event.id)) {
        _selectedIds.remove(event.id);
      } else {
        _selectedIds.add(event.id);
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
    final events = await ref.read(eventRepositoryProvider).listAll();
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final result = await showEventProjectFormDialog(context, title: 'New event');
    if (result == null) return;
    await ref.read(eventRepositoryProvider).create(
          name: result.name,
          description: result.description,
          startsAt: result.startsAt,
          endsAt: result.endsAt,
        );
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<void> _edit(Event event) async {
    final result = await showEventProjectFormDialog(
      context,
      title: 'Edit event',
      initialName: event.name,
      initialDescription: event.description,
      initialStartsAt: event.startsAt,
      initialEndsAt: event.endsAt,
    );
    if (result == null) return;
    await ref.read(eventRepositoryProvider).update(
          event.id,
          name: result.name,
          description: result.description,
          startsAt: result.startsAt,
          endsAt: result.endsAt,
        );
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final repo = ref.read(eventRepositoryProvider);
    var budgetCount = 0;
    for (final id in _selectedIds) {
      budgetCount += await repo.budgetCount(id);
    }
    if (!mounted) return;
    final message = budgetCount > 0
        ? 'These $count events have $budgetCount budget(s) that will also be deleted. Continue?'
        : 'Delete $count selected event(s)?';
    final confirmed = await showConfirmDialog(context, title: 'Delete events', message: message, destructive: true);
    if (!confirmed) return;
    for (final id in _selectedIds) {
      await repo.delete(id);
    }
    setState(() => _selectedIds.clear());
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : Text(translations?.t('settings_nav.events') ?? 'Events'),
        leading: _selectionMode
            ? IconButton(icon: const Icon(LucideIcons.x300), onPressed: () => setState(() => _selectedIds.clear()))
            : null,
        actions: _selectionMode
            ? [IconButton(icon: const Icon(LucideIcons.trash2300), onPressed: _deleteSelected)]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final event = _events[index];
                final selected = _selectedIds.contains(event.id);
                return ListTile(
                  selected: selected,
                  leading: _selectionMode ? Checkbox(value: selected, onChanged: (_) => _toggleSelection(event)) : null,
                  title: Text(event.name),
                  subtitle: event.description == null ? null : Text(event.description!),
                  trailing: _selectionMode
                      ? null
                      : IconButton(icon: const Icon(LucideIcons.pencil300), onPressed: () => _edit(event)),
                  onLongPress: () => _toggleSelection(event),
                  onTap: _selectionMode ? () => _toggleSelection(event) : null,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(LucideIcons.plus300)),
    );
  }
}

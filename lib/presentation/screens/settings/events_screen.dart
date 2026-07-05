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

  Future<void> _delete(Event event) async {
    final repo = ref.read(eventRepositoryProvider);
    final budgetCount = await repo.budgetCount(event.id);
    if (!mounted) return;
    final message = budgetCount > 0
        ? 'This event has $budgetCount budget(s) that will also be deleted. Continue?'
        : 'Delete this event?';
    final confirmed = await showConfirmDialog(context, title: 'Delete event', message: message, destructive: true);
    if (!confirmed) return;
    await repo.delete(event.id);
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(title: Text(translations?.t('settings_nav.events') ?? 'Events')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final event = _events[index];
                return ListTile(
                  title: Text(event.name),
                  subtitle: event.description == null ? null : Text(event.description!),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(event)),
                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(event)),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(Icons.add)),
    );
  }
}

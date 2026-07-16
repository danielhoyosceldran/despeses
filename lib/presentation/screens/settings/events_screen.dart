import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
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

  Future<bool> _confirmDelete(Event event) async {
    final budgetCount = await ref.read(eventRepositoryProvider).budgetCount(event.id);
    if (!mounted) return false;
    final translations = ref.read(translationsProvider).asData?.value;
    final message = budgetCount > 0
        ? (translations?.t('common.delete_with_budgets') ??
                '"{{name}}" has {{count}} budget(s) that will also be deleted. Continue?')
            .replaceAll('{{name}}', event.name)
            .replaceAll('{{count}}', '$budgetCount')
        : (translations?.t('common.delete_named') ?? 'Delete "{{name}}"?').replaceAll('{{name}}', event.name);
    return showConfirmDialog(
      context,
      title: translations?.t('events.delete_title') ?? 'Delete event',
      message: message,
      destructive: true,
    );
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
      appBar: AppBar(),
      body: Column(
        children: [
          PageTitleHeader(translations?.t('settings_nav.events') ?? 'Events'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      return EntityListTile(
                        id: event.id,
                        title: event.name,
                        subtitle: event.description,
                        onEdit: () => _edit(event),
                        confirmDelete: () => _confirmDelete(event),
                        onDeleted: () => _delete(event),
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

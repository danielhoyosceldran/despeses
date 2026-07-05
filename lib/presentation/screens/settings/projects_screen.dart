import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/event_project_form_dialog.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  List<Project> _projects = [];
  bool _loading = true;
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _toggleSelection(Project project) {
    setState(() {
      if (_selectedIds.contains(project.id)) {
        _selectedIds.remove(project.id);
      } else {
        _selectedIds.add(project.id);
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
    final projects = await ref.read(projectRepositoryProvider).listAll();
    setState(() {
      _projects = projects;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final result = await showEventProjectFormDialog(context, title: 'New project');
    if (result == null) return;
    await ref.read(projectRepositoryProvider).create(
          name: result.name,
          description: result.description,
          startsAt: result.startsAt,
          endsAt: result.endsAt,
        );
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<void> _edit(Project project) async {
    final result = await showEventProjectFormDialog(
      context,
      title: 'Edit project',
      initialName: project.name,
      initialDescription: project.description,
      initialStartsAt: project.startsAt,
      initialEndsAt: project.endsAt,
    );
    if (result == null) return;
    await ref.read(projectRepositoryProvider).update(
          project.id,
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
    final repo = ref.read(projectRepositoryProvider);
    var budgetCount = 0;
    for (final id in _selectedIds) {
      budgetCount += await repo.budgetCount(id);
    }
    if (!mounted) return;
    final message = budgetCount > 0
        ? 'These $count projects have $budgetCount budget(s) that will also be deleted. Continue?'
        : 'Delete $count selected project(s)?';
    final confirmed = await showConfirmDialog(context, title: 'Delete projects', message: message, destructive: true);
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
            : Text(translations?.t('settings_nav.projects') ?? 'Projects'),
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
              itemCount: _projects.length,
              itemBuilder: (context, index) {
                final project = _projects[index];
                final selected = _selectedIds.contains(project.id);
                return ListTile(
                  selected: selected,
                  leading: _selectionMode ? Checkbox(value: selected, onChanged: (_) => _toggleSelection(project)) : null,
                  title: Text(project.name),
                  subtitle: project.description == null ? null : Text(project.description!),
                  trailing: _selectionMode
                      ? null
                      : IconButton(icon: const Icon(LucideIcons.pencil300), onPressed: () => _edit(project)),
                  onLongPress: () => _toggleSelection(project),
                  onTap: _selectionMode ? () => _toggleSelection(project) : null,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(LucideIcons.plus300)),
    );
  }
}

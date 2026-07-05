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

  Future<void> _delete(Project project) async {
    final repo = ref.read(projectRepositoryProvider);
    final budgetCount = await repo.budgetCount(project.id);
    if (!mounted) return;
    final message = budgetCount > 0
        ? 'This project has $budgetCount budget(s) that will also be deleted. Continue?'
        : 'Delete this project?';
    final confirmed = await showConfirmDialog(context, title: 'Delete project', message: message, destructive: true);
    if (!confirmed) return;
    await repo.delete(project.id);
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(title: Text(translations?.t('settings_nav.projects') ?? 'Projects')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _projects.length,
              itemBuilder: (context, index) {
                final project = _projects[index];
                return ListTile(
                  title: Text(project.name),
                  subtitle: project.description == null ? null : Text(project.description!),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(project)),
                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(project)),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(Icons.add)),
    );
  }
}

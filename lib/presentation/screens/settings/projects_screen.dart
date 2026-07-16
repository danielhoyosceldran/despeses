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

  Future<bool> _confirmDelete(Project project) async {
    final budgetCount = await ref.read(projectRepositoryProvider).budgetCount(project.id);
    if (!mounted) return false;
    final translations = ref.read(translationsProvider).asData?.value;
    final message = budgetCount > 0
        ? (translations?.t('common.delete_with_budgets') ??
                '"{{name}}" has {{count}} budget(s) that will also be deleted. Continue?')
            .replaceAll('{{name}}', project.name)
            .replaceAll('{{count}}', '$budgetCount')
        : (translations?.t('common.delete_named') ?? 'Delete "{{name}}"?').replaceAll('{{name}}', project.name);
    return showConfirmDialog(
      context,
      title: translations?.t('projects.delete_title') ?? 'Delete project',
      message: message,
      destructive: true,
    );
  }

  Future<void> _delete(Project project) async {
    final index = _projects.indexOf(project);
    setState(() => _projects.remove(project));
    try {
      await ref.read(projectRepositoryProvider).delete(project.id);
      ref.read(referenceDataCacheProvider).invalidate();
    } catch (_) {
      if (index >= 0) setState(() => _projects.insert(index, project));
      if (mounted) {
        final translations = ref.read(translationsProvider).asData?.value;
        showAppToast(
          context,
          (translations?.t('common.error_delete_named') ?? 'Could not delete "{{name}}"')
              .replaceAll('{{name}}', project.name),
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
          PageTitleHeader(translations?.t('settings_nav.projects') ?? 'Projects'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: _projects.length,
                    itemBuilder: (context, index) {
                      final project = _projects[index];
                      return EntityListTile(
                        id: project.id,
                        title: project.name,
                        subtitle: project.description,
                        onEdit: () => _edit(project),
                        confirmDelete: () => _confirmDelete(project),
                        onDeleted: () => _delete(project),
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

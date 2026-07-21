import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/entity_form_dialog.dart';
import '../../widgets/entity_list_tile.dart';
import '../../widgets/page_title_header.dart';

class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  ConsumerState<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  List<PaymentMethod> _methods = [];
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
    final methods = await ref.read(paymentMethodRepositoryProvider).listAll();
    setState(() {
      _methods = methods;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final result = await showEntityFormDialog(context, title: 'New payment method', withColor: false);
    if (result == null) return;
    await ref.read(paymentMethodRepositoryProvider).create(name: result.name, icon: result.icon);
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<void> _edit(PaymentMethod method, String currentName) async {
    final result = await showEntityFormDialog(
      context,
      title: 'Edit payment method',
      initialName: currentName,
      initialIcon: method.icon,
      withColor: false,
    );
    if (result == null) return;
    final repo = ref.read(paymentMethodRepositoryProvider);
    if (result.name != currentName) await repo.rename(method.id, result.name);
    await repo.updateIcon(method.id, result.icon);
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
  }

  Future<void> _delete(PaymentMethod method) async {
    final index = _methods.indexOf(method);
    setState(() => _methods.remove(method));
    try {
      await ref.read(paymentMethodRepositoryProvider).delete(method.id);
      ref.read(referenceDataCacheProvider).invalidate();
    } catch (_) {
      if (index >= 0) setState(() => _methods.insert(index, method));
      if (mounted) {
        final translations = ref.read(translationsProvider).asData?.value;
        showAppToast(
          context,
          (translations?.t('common.error_delete_named') ?? 'Could not delete "{{name}}"')
              .replaceAll('{{name}}', method.name),
          variant: ToastVariant.error,
        );
      }
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = List<PaymentMethod>.from(_methods);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    setState(() => _methods = reordered);
    await ref.read(paymentMethodRepositoryProvider).reorder(reordered.map((m) => m.id).toList());
    ref.read(referenceDataCacheProvider).invalidate();
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
    final toDelete = _methods.where((m) => _selected.contains(m.id)).toList();
    final translations = ref.read(translationsProvider).asData?.value;
    final confirmed = await showConfirmDialog(
      context,
      title: translations?.t('payment_methods.delete_title') ?? 'Delete payment method',
      message: (translations?.t('common.delete_selected') ?? 'Delete {{count}} selected item(s)?')
          .replaceAll('{{count}}', '${toDelete.length}'),
      destructive: true,
    );
    if (!confirmed) return;
    for (final method in toDelete) {
      await _delete(method);
    }
    _exitSelection();
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;

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
          PageTitleHeader(translations?.t('settings_nav.payment_methods') ?? 'Payment methods'),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    buildDefaultDragHandles: false,
                    itemCount: _methods.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                final method = _methods[index];
                final label = translations == null
                    ? method.name
                    : displayNameFor(translations, name: method.name, isDefault: method.isDefault);
                return EntityListTile(
                  key: ValueKey(method.id),
                  id: method.id,
                  title: label,
                  icon: method.icon,
                  onEdit: () => _edit(method, label),
                  onLongPress: () => _enterSelection(method.id),
                  selectionMode: _selectionMode,
                  selected: _selected.contains(method.id),
                  onSelectedChanged: (v) => _setSelected(method.id, v),
                  reorderIndex: index,
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

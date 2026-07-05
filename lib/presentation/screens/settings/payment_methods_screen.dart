import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/entity_form_dialog.dart';

class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  ConsumerState<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  List<PaymentMethod> _methods = [];
  bool _loading = true;
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _toggleSelection(PaymentMethod method) {
    if (method.isDefault) return;
    setState(() {
      if (_selectedIds.contains(method.id)) {
        _selectedIds.remove(method.id);
      } else {
        _selectedIds.add(method.id);
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

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete payment methods',
      message: 'Delete $count selected payment method(s)? Expenses using them will keep their data but lose the reference.',
      destructive: true,
    );
    if (!confirmed) return;
    final repo = ref.read(paymentMethodRepositoryProvider);
    for (final id in _selectedIds) {
      await repo.delete(id);
    }
    setState(() => _selectedIds.clear());
    ref.read(referenceDataCacheProvider).invalidate();
    _load();
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

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selectedIds.length} selected')
            : Text(translations?.t('settings_nav.payment_methods') ?? 'Payment methods'),
        leading: _selectionMode
            ? IconButton(icon: const Icon(LucideIcons.x300), onPressed: () => setState(() => _selectedIds.clear()))
            : null,
        actions: _selectionMode
            ? [IconButton(icon: const Icon(LucideIcons.trash2300), onPressed: _deleteSelected)]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
              itemCount: _methods.length,
              onReorder: _reorder,
              itemBuilder: (context, index) {
                final method = _methods[index];
                final selected = _selectedIds.contains(method.id);
                final label = translations == null
                    ? method.name
                    : displayNameFor(translations, name: method.name, isDefault: method.isDefault);
                return ListTile(
                  key: ValueKey(method.id),
                  selected: selected,
                  leading: _selectionMode
                      ? Checkbox(value: selected, onChanged: method.isDefault ? null : (_) => _toggleSelection(method))
                      : null,
                  title: Text(label),
                  trailing: _selectionMode
                      ? null
                      : IconButton(icon: const Icon(LucideIcons.pencil300), onPressed: () => _edit(method, label)),
                  onLongPress: () => _toggleSelection(method),
                  onTap: _selectionMode ? () => _toggleSelection(method) : null,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(LucideIcons.plus300)),
    );
  }
}

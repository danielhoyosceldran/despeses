import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/database.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/entity_form_dialog.dart';
import '../../widgets/entity_list_tile.dart';

class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  ConsumerState<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  List<PaymentMethod> _methods = [];
  bool _loading = true;

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

  Future<bool> _confirmDelete(String label) {
    return showConfirmDialog(
      context,
      title: 'Delete payment method',
      message: 'Delete "$label"? Expenses using it will keep their data but lose the reference.',
      destructive: true,
    );
  }

  Future<void> _delete(PaymentMethod method) async {
    setState(() => _methods.remove(method));
    await ref.read(paymentMethodRepositoryProvider).delete(method.id);
    ref.read(referenceDataCacheProvider).invalidate();
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
        title: Text(translations?.t('settings_nav.payment_methods') ?? 'Payment methods'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
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
                  onEdit: () => _edit(method, label),
                  confirmDelete: method.isDefault ? null : () => _confirmDelete(label),
                  onDeleted: () => _delete(method),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(LucideIcons.plus300)),
    );
  }
}

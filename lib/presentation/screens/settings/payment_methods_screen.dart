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
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete payment method',
      message: 'Expenses using it will keep their data but lose this payment method reference.',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(paymentMethodRepositoryProvider).delete(method.id);
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
      appBar: AppBar(title: Text(translations?.t('settings_nav.payment_methods') ?? 'Payment methods')),
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
                return ListTile(
                  key: ValueKey(method.id),
                  title: Text(label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(method, label)),
                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(method)),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: _create, child: const Icon(Icons.add)),
    );
  }
}

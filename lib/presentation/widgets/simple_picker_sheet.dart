import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Single-select list sheet (payment method / event / project): tapping an
/// item selects it and closes immediately (auto-advance, plan §3.1).
Future<T?> showSimplePickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: SimplePickerContent<T>(
          title: title,
          items: items,
          labelOf: labelOf,
          onSelected: (item) => Navigator.of(context).pop(item),
        ),
      ),
    ),
  );
}

/// Embeddable body of the simple picker, usable inside a [BottomActionPanel]
/// or a modal sheet.
class SimplePickerContent<T> extends StatelessWidget {
  const SimplePickerContent({
    super.key,
    required this.title,
    required this.items,
    required this.labelOf,
    required this.onSelected,
  });

  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                title: Text(labelOf(item)),
                onTap: () => onSelected(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

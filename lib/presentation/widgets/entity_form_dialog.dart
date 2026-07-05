import 'package:flutter/material.dart';

/// Chart palette from `STYLE_FLUTTER.md` §2 — reused here as the color picker
/// choices for categories/tags (only real accent color usage besides the
/// single app accent).
const chartPalette = [
  Color(0xFFF94144),
  Color(0xFFF3722C),
  Color(0xFFF8961E),
  Color(0xFFF9C74F),
  Color(0xFFE9D8A6),
  Color(0xFF90BE6D),
  Color(0xFF43AA8B),
  Color(0xFF0A9396),
  Color(0xFF005F73),
  Color(0xFF577590),
  Color(0xFF277DA1),
  Color(0xFFCA6702),
  Color(0xFFBB3E03),
  Color(0xFFAE2012),
  Color(0xFF9B2226),
];

String colorToHex(Color c) =>
    '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

Color? hexToColor(String? hex) {
  if (hex == null) return null;
  final clean = hex.replaceFirst('#', '');
  return Color(int.parse('FF$clean', radix: 16));
}

class EntityFormResult {
  const EntityFormResult({required this.name, this.color, this.icon});

  final String name;
  final String? color;
  final String? icon;
}

/// Shared create/edit dialog for the entities that only need name + optional
/// color + optional icon text (categories, tags, payment methods).
Future<EntityFormResult?> showEntityFormDialog(
  BuildContext context, {
  required String title,
  String initialName = '',
  String? initialColor,
  String? initialIcon,
  bool withColor = true,
  bool withIcon = true,
}) async {
  final nameController = TextEditingController(text: initialName);
  final iconController = TextEditingController(text: initialIcon ?? '');
  var selectedColor = initialColor;

  return showDialog<EntityFormResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              if (withIcon) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: iconController,
                  maxLength: 50,
                  decoration: const InputDecoration(labelText: 'Icon (optional)'),
                ),
              ],
              if (withColor) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final color in chartPalette)
                      GestureDetector(
                        onTap: () => setState(() => selectedColor = colorToHex(color)),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            border: Border.all(
                              width: selectedColor == colorToHex(color) ? 2 : 0,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(
                EntityFormResult(
                  name: name,
                  color: selectedColor,
                  icon: iconController.text.trim().isEmpty ? null : iconController.text.trim(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

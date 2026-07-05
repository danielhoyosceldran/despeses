import 'package:flutter/material.dart';

class EventProjectFormResult {
  const EventProjectFormResult({
    required this.name,
    this.description,
    this.startsAt,
    this.endsAt,
  });

  final String name;
  final String? description;
  final DateTime? startsAt;
  final DateTime? endsAt;
}

Future<EventProjectFormResult?> showEventProjectFormDialog(
  BuildContext context, {
  required String title,
  String initialName = '',
  String? initialDescription,
  DateTime? initialStartsAt,
  DateTime? initialEndsAt,
}) async {
  final nameController = TextEditingController(text: initialName);
  final descriptionController = TextEditingController(text: initialDescription ?? '');
  var startsAt = initialStartsAt;
  var endsAt = initialEndsAt;

  return showDialog<EventProjectFormResult>(
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
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startsAt ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => startsAt = picked);
                      },
                      child: Text(startsAt == null
                          ? 'Start date'
                          : '${startsAt!.year}-${startsAt!.month.toString().padLeft(2, '0')}-${startsAt!.day.toString().padLeft(2, '0')}'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: endsAt ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => endsAt = picked);
                      },
                      child: Text(endsAt == null
                          ? 'End date'
                          : '${endsAt!.year}-${endsAt!.month.toString().padLeft(2, '0')}-${endsAt!.day.toString().padLeft(2, '0')}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(
                EventProjectFormResult(
                  name: name,
                  description: descriptionController.text.trim().isEmpty
                      ? null
                      : descriptionController.text.trim(),
                  startsAt: startsAt,
                  endsAt: endsAt,
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

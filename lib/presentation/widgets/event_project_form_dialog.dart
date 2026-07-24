import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../../core/format/date.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_theme.dart';

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
  required Translations translations,
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
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(labelText: translations.t('common.name')),
              ),
              const SizedBox(height: AppSpacing.smMd),
              TextField(
                controller: descriptionController,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(labelText: translations.t('common.description_optional')),
              ),
              const SizedBox(height: AppSpacing.smMd),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: startsAt == null ? translations.t('common.starts_at') : formatDate(startsAt!),
                      isSet: startsAt != null,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startsAt ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => startsAt = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _DateField(
                      label: endsAt == null ? translations.t('common.ends_at') : formatDate(endsAt!),
                      isSet: endsAt != null,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: endsAt ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => endsAt = picked);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(translations.t('common.cancel'))),
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
            child: Text(translations.t('common.save')),
          ),
        ],
      ),
    ),
  );
}

/// Filled tappable field matching the input style, used to open a date picker.
class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.isSet, required this.onTap});

  final String label;
  final bool isSet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppDimens.radiusButton),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusButton),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd, vertical: AppSpacing.md),
          child: Row(
            children: [
              Icon(LucideIcons.calendar300, size: 18, color: colors.textMuted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: isSet ? colors.text : colors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

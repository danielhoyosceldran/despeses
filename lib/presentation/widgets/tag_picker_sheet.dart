import 'package:flutter/material.dart';

import '../../core/i18n/display_name.dart';
import '../../core/i18n/translations.dart';
import '../../data/database.dart';

/// Grouped multi-select tag picker (plan §3.1): chips grouped by tag group,
/// with an explicit "Next" button — unlike other fields, tag selection does
/// not auto-advance because it is multi-select.
Future<List<String>?> showTagPickerSheet(
  BuildContext context, {
  required List<TagGroup> groups,
  required List<Tag> tags,
  required List<String> initialSelectedIds,
  required Translations translations,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: TagPickerContent(
          groups: groups,
          tags: tags,
          initialSelectedIds: initialSelectedIds,
          translations: translations,
          onDone: (selected) => Navigator.of(context).pop(selected),
        ),
      ),
    ),
  );
}

/// Embeddable body of the tag picker, usable inside a [BottomActionPanel] or
/// a modal sheet.
class TagPickerContent extends StatefulWidget {
  const TagPickerContent({
    super.key,
    required this.groups,
    required this.tags,
    required this.initialSelectedIds,
    required this.translations,
    required this.onDone,
  });

  final List<TagGroup> groups;
  final List<Tag> tags;
  final List<String> initialSelectedIds;
  final Translations translations;
  final ValueChanged<List<String>> onDone;

  @override
  State<TagPickerContent> createState() => TagPickerContentState();
}

/// Public so the host screen can read the current selection and trigger
/// [onDone] from an external "Next" button placed next to Save.
class TagPickerContentState extends State<TagPickerContent> {
  late final Set<String> _selected = widget.initialSelectedIds.toSet();

  List<String> get selectedIds => _selected.toList();

  void confirm() => widget.onDone(selectedIds);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              for (final group in widget.groups)
                if (widget.tags.any((t) => t.tagGroupId == group.id))
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tagGroupDisplayName(widget.translations, group.name),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in widget.tags.where((t) => t.tagGroupId == group.id))
                              FilterChip(
                                label: Text(displayNameFor(
                                  widget.translations,
                                  name: tag.name,
                                  isDefault: tag.isDefault,
                                )),
                                selected: _selected.contains(tag.id),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selected.add(tag.id);
                                    } else {
                                      _selected.remove(tag.id);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Dumb shell for the settings CRUD list rows (categories, tags, tag groups,
/// payment methods, events, projects).
///
/// Gestures: long-press drags to reorder (on reorderable lists), swipe right
/// edits, swipe left deletes after confirmation.
class EntityListTile extends StatelessWidget {
  const EntityListTile({
    super.key,
    required this.id,
    required this.title,
    this.subtitle,
    this.leadingColor,
    this.onEdit,
    this.confirmDelete,
    this.onDeleted,
    this.onTap,
  });

  /// Stable entity id, used to key the swipe gesture state.
  final String id;
  final String title;
  final String? subtitle;

  /// Entity color, shown as a small dot.
  final Color? leadingColor;

  /// Swipe right to edit; null disables the gesture.
  final VoidCallback? onEdit;

  /// Swipe left to delete: asks the user to confirm and returns whether the
  /// row should be removed. Null disables the gesture (defaults, "Ungrouped").
  final Future<bool> Function()? confirmDelete;

  /// Called once the delete swipe is confirmed and the row is dismissed. Must
  /// synchronously remove the entity from the list backing this tile.
  final VoidCallback? onDeleted;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;
    final direction = onEdit != null && confirmDelete != null
        ? DismissDirection.horizontal
        : onEdit != null
            ? DismissDirection.startToEnd
            : confirmDelete != null
                ? DismissDirection.endToStart
                : DismissDirection.none;
    return Dismissible(
      key: ValueKey('entity-tile-$id'),
      direction: direction,
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onEdit!();
          return false;
        }
        return confirmDelete!();
      },
      onDismissed: (_) => onDeleted?.call(),
      background: Container(
        color: colors.accent,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(LucideIcons.pencil300, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(LucideIcons.trash2300, color: Colors.white),
      ),
      child: ListTile(
        leading: leadingColor == null ? null : CircleAvatar(backgroundColor: leadingColor, radius: 8),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        onTap: onTap,
      ),
    );
  }
}

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Dumb shell for the settings CRUD list rows (categories, tags, tag groups,
/// payment methods, events, projects).
///
/// Leading is a rounded-square avatar tinted with the entity color: it shows
/// the entity's [icon] (a free-text emoji) when set, otherwise the title's
/// initial. Gestures: long-press drags to reorder (on reorderable lists),
/// swipe right edits, swipe left deletes after confirmation.
class EntityListTile extends StatelessWidget {
  const EntityListTile({
    super.key,
    required this.id,
    required this.title,
    this.subtitle,
    this.leadingColor,
    this.icon,
    this.onEdit,
    this.confirmDelete,
    this.onDeleted,
    this.onTap,
    this.showDivider = true,
  });

  /// Stable entity id, used to key the swipe gesture state.
  final String id;
  final String title;
  final String? subtitle;

  /// Entity color; tints the avatar and colors its initial. Falls back to the
  /// app accent when null.
  final Color? leadingColor;

  /// Free-text emoji stored on the entity; rendered inside the avatar when set.
  final String? icon;

  /// Swipe right to edit; null disables the gesture.
  final VoidCallback? onEdit;

  /// Swipe left to delete: asks the user to confirm and returns whether the
  /// row should be removed. Null disables the gesture (defaults, "Ungrouped").
  final Future<bool> Function()? confirmDelete;

  /// Called once the delete swipe is confirmed and the row is dismissed. Must
  /// synchronously remove the entity from the list backing this tile.
  final VoidCallback? onDeleted;

  final VoidCallback? onTap;

  /// Show a hairline divider below the row, inset to align under the text.
  final bool showDivider;

  static const double _avatarSize = 44;
  static const double _gap = AppSpacing.smMd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tint = leadingColor ?? colors.accent;
    final direction = onEdit != null && confirmDelete != null
        ? DismissDirection.horizontal
        : onEdit != null
            ? DismissDirection.startToEnd
            : confirmDelete != null
                ? DismissDirection.endToStart
                : DismissDirection.none;

    final hasIcon = icon != null && icon!.trim().isNotEmpty;
    final initial = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();

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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Icon(LucideIcons.pencil300, color: colors.onAccent),
      ),
      secondaryBackground: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Icon(LucideIcons.trash2300, color: colors.onAccent),
      ),
      child: Material(
        color: colors.surface,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smMd),
                child: Row(
                  children: [
                    Container(
                      width: _avatarSize,
                      height: _avatarSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: hasIcon
                          ? Text(icon!.trim(), style: const TextStyle(fontSize: 20))
                          : Text(
                              initial,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tint),
                            ),
                    ),
                    const SizedBox(width: _gap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Icon(LucideIcons.chevronRight300, size: 20, color: colors.textMuted),
                    ],
                  ],
                ),
              ),
              if (showDivider)
                Divider(
                  color: colors.divider,
                  height: 1,
                  indent: AppSpacing.md + _avatarSize + _gap,
                  endIndent: AppSpacing.md,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Dumb shell for the settings CRUD list rows (categories, tags, tag groups,
/// payment methods, events, projects).
///
/// Leading is a rounded-square avatar tinted with the entity color: it shows
/// the entity's [icon] (a free-text emoji) when set, otherwise the title's
/// initial. Two modes:
/// - normal: tap opens/drills into the row ([onTap]); long-press enters
///   selection mode ([onLongPress]).
/// - selection ([selectionMode]): leading swaps to a checkbox, trailing shows
///   an edit pencil and (when [reorderIndex] is set) a drag handle; tap
///   toggles the checkbox instead of firing [onTap].
class EntityListTile extends StatelessWidget {
  const EntityListTile({
    super.key,
    required this.id,
    required this.title,
    this.subtitle,
    this.leadingColor,
    this.icon,
    this.onEdit,
    this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectedChanged,
    this.reorderIndex,
    this.showDivider = true,
  });

  /// Stable entity id.
  final String id;
  final String title;
  final String? subtitle;

  /// Entity color; tints the avatar and colors its initial. Falls back to the
  /// app accent when null.
  final Color? leadingColor;

  /// Free-text emoji stored on the entity; rendered inside the avatar when set.
  final String? icon;

  /// Opens the edit dialog for this row; shown as a trailing pencil in
  /// selection mode. Null hides the pencil.
  final VoidCallback? onEdit;

  final VoidCallback? onTap;

  /// Enters selection mode for the whole list, selecting this row. Ignored
  /// while [selectionMode] is already true.
  final VoidCallback? onLongPress;

  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  /// Index in the enclosing `ReorderableListView`; when set, a drag handle is
  /// shown in selection mode. Null hides the handle (non-reorderable lists).
  final int? reorderIndex;

  /// Show a hairline divider below the row, inset to align under the text.
  final bool showDivider;

  static const double _avatarSize = 44;
  static const double _gap = AppSpacing.smMd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tint = leadingColor ?? colors.accent;
    final hasIcon = icon != null && icon!.trim().isNotEmpty;
    final initial = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();

    return Material(
      color: colors.surface,
      child: InkWell(
        onTap: selectionMode ? () => onSelectedChanged?.call(!selected) : onTap,
        onLongPress: selectionMode ? null : onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smMd),
              child: Row(
                children: [
                  if (selectionMode)
                    Checkbox(
                      value: selected,
                      onChanged: onSelectedChanged == null ? null : (v) => onSelectedChanged!(v ?? false),
                    )
                  else
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
                  if (selectionMode) ...[
                    if (onEdit != null)
                      IconButton(
                        icon: const Icon(LucideIcons.pencil300, size: 20),
                        onPressed: onEdit,
                      ),
                    if (reorderIndex != null)
                      ReorderableDragStartListener(
                        index: reorderIndex!,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                          child: Icon(LucideIcons.gripVertical300, size: 20, color: colors.textMuted),
                        ),
                      ),
                  ] else if (onTap != null) ...[
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
    );
  }
}

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Settings-hub row: leading icon in an accent-tinted rounded square, title,
/// and trailing chevron, optionally separated by a hairline divider. Shares
/// the same metrics as [EntityListTile] (44px avatar, radius 14, md/smMd
/// padding, inset divider) so hub rows and in-page CRUD rows line up.
class HairlineListTile extends StatelessWidget {
  const HairlineListTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  static const double _avatarSize = 44;
  static const double _gap = AppSpacing.smMd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smMd),
              child: Row(
                children: [
                  Container(
                    width: _avatarSize,
                    height: _avatarSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: pillBackground(colors.accent),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: colors.accent, size: 20),
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
                  const SizedBox(width: AppSpacing.sm),
                  trailing ?? Icon(LucideIcons.chevronRight300, size: 20, color: colors.textMuted),
                ],
              ),
            ),
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
    );
  }
}

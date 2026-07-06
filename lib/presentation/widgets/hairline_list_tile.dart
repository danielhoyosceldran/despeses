import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// List row with the leading icon in an accent-tinted circle, title, and
/// trailing chevron, optionally separated by a hairline divider — meant to
/// be stacked inside an [AppCard]-style grouped list.
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: pillBackground(colors.accent), shape: BoxShape.circle),
            child: Icon(icon, color: colors.accent, size: 20),
          ),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: trailing ?? Icon(LucideIcons.chevronRight300, color: colors.textMuted),
          onTap: onTap,
        ),
        if (showDivider) Divider(color: colors.divider, height: 1),
      ],
    );
  }
}

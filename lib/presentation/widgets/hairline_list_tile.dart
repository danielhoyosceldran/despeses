import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Flat list row with an accent-tinted leading icon, title, and trailing
/// chevron, separated by a hairline divider — replaces the boxed `ListTile`
/// + `Card` look with the mockups' flush divider list.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: colors.accent),
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

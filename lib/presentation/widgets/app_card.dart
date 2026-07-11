import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Surface card from the mock: `bg-card`, rounded corners, hairline translucent
/// border (`border/50`), no shadow by default. Use [AppCard.large] for the
/// 24px "panel" radius (analytics / settings).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin,
    this.radius = AppDimens.radiusCard,
    this.border = true,
    this.color,
    this.clip = false,
  });

  /// Larger 24px panel radius (`rounded-3xl`) for analytics / settings cards.
  const AppCard.large({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin,
    this.border = true,
    this.color,
    this.clip = false,
  }) : radius = AppDimens.radiusPanel;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final bool border;
  final Color? color;

  /// Clip the child to the rounded corners (needed when children draw their
  /// own dividers/fills to the card edge, e.g. the settings list).
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: margin,
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: colors.borderSoft, width: 1) : null,
      ),
      child: child,
    );
  }
}

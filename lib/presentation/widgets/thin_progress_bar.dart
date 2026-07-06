import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Rounded progress bar used for budget progress — [fillColor] is normally
/// the budget's category color, overridden to the semantic "over" color by
/// the caller once spent exceeds the target. Animates to its value on mount.
class ThinProgressBar extends StatelessWidget {
  const ThinProgressBar({super.key, required this.value, required this.fillColor, this.height = 6});

  final double value;
  final Color fillColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: AppDimens.animNormal,
          curve: AppDimens.animCurve,
          builder: (context, animatedValue, _) => Stack(
            children: [
              Container(
                height: height,
                width: constraints.maxWidth,
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                ),
              ),
              Container(
                height: height,
                width: constraints.maxWidth * animatedValue,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  gradient: LinearGradient(
                    colors: [fillColor.withValues(alpha: 0.75), fillColor],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

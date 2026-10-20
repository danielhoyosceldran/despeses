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
    // The fill is a full-width pill slid left by the missing fraction and
    // clipped by the track: animating it only moves paint, where animating a
    // width factor would re-layout the bar every frame. No LayoutBuilder, so
    // the bar can still report intrinsic dimensions (needed when a parent
    // IntrinsicHeight measures it, e.g. the dashboard budget grid).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: AppDimens.animNormal,
      curve: AppDimens.animCurve,
      builder: (context, animatedValue, _) => ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        child: Container(
          height: height,
          width: double.infinity,
          color: colors.surfaceAlt,
          child: FractionalTranslation(
            translation: Offset(animatedValue - 1, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(AppDimens.radiusPill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

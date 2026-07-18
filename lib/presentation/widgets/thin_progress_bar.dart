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
    // No LayoutBuilder: the fill uses FractionallySizedBox so the bar can still
    // report intrinsic dimensions (needed when a parent IntrinsicHeight measures
    // it, e.g. the dashboard budget grid).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: AppDimens.animNormal,
      curve: AppDimens.animCurve,
      builder: (context, animatedValue, _) => Stack(
        children: [
          Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            ),
          ),
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: animatedValue,
              child: Container(
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

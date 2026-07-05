import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Thin full-width fill bar (mockup style) used for budget progress —
/// [fillColor] is normally the budget's category color, overridden to the
/// semantic "over" color by the caller once spent exceeds the target.
class ThinProgressBar extends StatelessWidget {
  const ThinProgressBar({super.key, required this.value, required this.fillColor, this.height = 3});

  final double value;
  final Color fillColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Container(height: height, width: constraints.maxWidth, color: colors.surfaceAlt),
            Container(height: height, width: constraints.maxWidth * value.clamp(0.0, 1.0), color: fillColor),
          ],
        );
      },
    );
  }
}

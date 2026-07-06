import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Corner radii, control sizes and motion tokens.
class AppDimens {
  static const radiusCard = 24.0;

  /// Top corners of bottom sheets.
  static const radiusSheet = 28.0;
  static const radiusPill = 100.0;
  static const radiusButton = 16.0;

  static const buttonHeight = 52.0;

  static const animFast = Duration(milliseconds: 200);
  static const animNormal = Duration(milliseconds: 300);
  static const animCurve = Curves.easeOutCubic;
}

/// Fixed 4·8·12·16·24·32·48·64 spacing scale — space is the primary
/// separator; borders only where space alone isn't enough.
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const smMd = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const xxxl = 64.0;
}

/// Single soft card shadow — the only shadow in the app.
class AppShadows {
  static List<BoxShadow> card(AppColors colors) => [
        BoxShadow(blurRadius: 24, offset: const Offset(0, 8), color: colors.shadow),
      ];
}

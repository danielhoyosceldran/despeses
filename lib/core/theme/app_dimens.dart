import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Corner radii, control sizes and motion tokens. Radii follow the mock:
/// rows/cards 16 (2xl), panels 24 (3xl), sheets 40, budget cards 12, pills full.
class AppDimens {
  /// Cards, stat tiles, transaction rows, form fields (`rounded-2xl`).
  static const radiusCard = 16.0;

  /// Large panels: analytics card, settings card (`rounded-3xl`).
  static const radiusPanel = 24.0;

  /// Budget card, slightly tighter than the rest (`rounded-xl`).
  static const radiusBudget = 12.0;

  /// Top corners of bottom sheets (`rounded-t-[2.5rem]`).
  static const radiusSheet = 40.0;
  static const radiusPill = 100.0;
  static const radiusButton = 16.0;

  static const buttonHeight = 56.0;

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

/// App shadows. Cards mostly rely on the hairline border; heavier shadows are
/// reserved for the FAB and bottom sheets (`shadow-xl` / `shadow-2xl`).
class AppShadows {
  static List<BoxShadow> card(AppColors colors) => [
        BoxShadow(blurRadius: 24, offset: const Offset(0, 8), color: colors.shadow),
      ];

  static List<BoxShadow> fab(AppColors colors) => [
        BoxShadow(blurRadius: 20, offset: const Offset(0, 8), color: colors.shadow),
      ];

  static List<BoxShadow> sheet(AppColors colors) => [
        BoxShadow(blurRadius: 40, offset: const Offset(0, -8), color: colors.shadow),
      ];
}

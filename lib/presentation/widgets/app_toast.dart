import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum ToastVariant { info, success, error, warning }

/// Floating rounded toast: neutral surface from the theme, semantic color
/// only on the icon.
void showAppToast(BuildContext context, String message, {ToastVariant variant = ToastVariant.info}) {
  final icon = switch (variant) {
    ToastVariant.info => LucideIcons.info300,
    ToastVariant.success => LucideIcons.checkCircle2300,
    ToastVariant.error => LucideIcons.circleAlert300,
    ToastVariant.warning => LucideIcons.triangleAlert300,
  };
  final semantic = context.semanticColors;
  final iconColor = switch (variant) {
    ToastVariant.info => context.appColors.accent,
    ToastVariant.success => semantic.income,
    ToastVariant.error => semantic.expense,
    ToastVariant.warning => semantic.refund,
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

import 'package:flutter/material.dart';

enum ToastVariant { info, success, error, warning }

/// Sober, hairline-bordered feedback (plan `STYLE_FLUTTER.md` §2): no tinted
/// background, no shadow — the semantic color lives only in icon/text.
void showAppToast(BuildContext context, String message, {ToastVariant variant = ToastVariant.info}) {
  final icon = switch (variant) {
    ToastVariant.info => Icons.info_outline,
    ToastVariant.success => Icons.check_circle_outline,
    ToastVariant.error => Icons.error_outline,
    ToastVariant.warning => Icons.warning_amber_outlined,
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        content: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

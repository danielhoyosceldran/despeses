import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';

/// Async-failure placeholder with a Retry action (X1). Used wherever a failed
/// `FutureBuilder`/`AsyncValue` would otherwise spin forever with no way out.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    super.key,
    required this.onRetry,
    this.message = 'Could not load this.',
  });

  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleAlert300, size: 40, color: colors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw300, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';

/// Centered month/year label flanked by prev/next chevrons in circular
/// surface buttons — the header row shared by Dashboard and Analytics
/// month pagers.
class MonthHeaderBar extends StatelessWidget {
  const MonthHeaderBar({super.key, required this.month, required this.onChangeMonth});

  final DateTime month;
  final void Function(int delta) onChangeMonth;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ChevronButton(icon: LucideIcons.chevronLeft300, onPressed: () => onChangeMonth(-1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            toBeginningOfSentenceCase(DateFormat.yMMMM().format(month)),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        _ChevronButton(icon: LucideIcons.chevronRight300, onPressed: () => onChangeMonth(1)),
      ],
    );
  }
}

class _ChevronButton extends StatelessWidget {
  const _ChevronButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: colors.surface,
        foregroundColor: colors.text,
        shape: const CircleBorder(),
      ),
    );
  }
}

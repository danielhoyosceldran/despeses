import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';

/// Centered uppercase month/year label flanked by prev/next chevrons — the
/// header row shared by Dashboard and Analytics month pagers.
class MonthHeaderBar extends StatelessWidget {
  const MonthHeaderBar({super.key, required this.month, required this.onChangeMonth});

  final DateTime month;
  final void Function(int delta) onChangeMonth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(LucideIcons.chevronLeft300), onPressed: () => onChangeMonth(-1)),
        Text(DateFormat.yMMMM().format(month).toUpperCase(), style: appHeaderStyle(colors)),
        IconButton(icon: const Icon(LucideIcons.chevronRight300), onPressed: () => onChangeMonth(1)),
      ],
    );
  }
}

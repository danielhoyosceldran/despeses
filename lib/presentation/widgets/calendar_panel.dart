import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';

/// Bottom-panel calendar (plan §3.2): month navigation, today marked, week
/// starts Monday. Replaces the native `showDatePicker`. Shared by the
/// transaction and recurring entry flows.
class CalendarPanel extends StatefulWidget {
  const CalendarPanel({super.key, required this.initial, required this.onSelected});

  final DateTime initial;
  final ValueChanged<DateTime> onSelected;

  @override
  State<CalendarPanel> createState() => _CalendarPanelState();
}

class _CalendarPanelState extends State<CalendarPanel> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final today = DateTime.now();
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final leadingBlanks = (firstOfMonth.weekday - DateTime.monday) % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.chevronLeft300),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              ),
              Text(DateFormat.yMMMM().format(_month), style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: const Icon(LucideIcons.chevronRight300),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.count(
              crossAxisCount: 7,
              children: [
                for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
                for (var d = 1; d <= daysInMonth; d++)
                  _DayCell(
                    day: d,
                    isToday: today.year == _month.year && today.month == _month.month && today.day == d,
                    onTap: () => widget.onSelected(DateTime(_month.year, _month.month, d)),
                    accent: colors.accent,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.isToday, required this.onTap, required this.accent});

  final int day;
  final bool isToday;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: isToday
              ? BoxDecoration(color: accent.withValues(alpha: 0.15), shape: BoxShape.circle)
              : null,
          child: Text('$day', style: isToday ? TextStyle(color: accent, fontWeight: FontWeight.w600) : null),
        ),
      ),
    );
  }
}

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../../core/format/date.dart';
import '../../core/theme/app_theme.dart';

class YearMonth {
  const YearMonth(this.year, this.month);

  final int year;
  final int month;

  String get key => '$year-${month.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) => other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// Own month picker (plan §3.2): a year stepper + a 12-month grid, used for
/// budgets of type `range` (start/end month) and `months` (multi-select).
Future<YearMonth?> showMonthPickerDialog(BuildContext context, {YearMonth? initial}) {
  return showDialog<YearMonth>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 300,
        height: 340,
        child: MonthPickerContent(
          initial: initial,
          onSelected: (yearMonth) => Navigator.of(context).pop(yearMonth),
        ),
      ),
    ),
  );
}

/// Embeddable body of the month picker (year stepper + 12-month grid),
/// usable inside a [BottomActionPanel] or a modal dialog.
class MonthPickerContent extends StatefulWidget {
  const MonthPickerContent({super.key, this.initial, required this.onSelected});

  final YearMonth? initial;
  final ValueChanged<YearMonth> onSelected;

  @override
  State<MonthPickerContent> createState() => _MonthPickerContentState();
}

class _MonthPickerContentState extends State<MonthPickerContent> {
  late int _year = widget.initial?.year ?? DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _YearChevron(icon: LucideIcons.chevronLeft300, onPressed: () => setState(() => _year--)),
              Text('$_year', style: Theme.of(context).textTheme.titleMedium),
              _YearChevron(icon: LucideIcons.chevronRight300, onPressed: () => setState(() => _year++)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: GridView.count(
              crossAxisCount: 3,
              // Localized month abbreviations (e.g. es "sept.", ca "set.")
              // run longer than the English 3-letter ones (R16) — lower
              // aspect ratio buys extra width so labels don't clip.
              childAspectRatio: 1.6,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              children: [
                for (var m = 1; m <= 12; m++)
                  _MonthCell(
                    label: formatMonthAbbrev(_year, m),
                    selected: widget.initial?.year == _year && widget.initial?.month == m,
                    onTap: () => widget.onSelected(YearMonth(_year, m)),
                    colors: colors,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _YearChevron extends StatelessWidget {
  const _YearChevron({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: colors.surfaceAlt,
        foregroundColor: colors.text,
        shape: const CircleBorder(),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? pillBackground(colors.accent) : colors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppDimens.radiusButton),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusButton),
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: FittedBox(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? colors.accent : colors.text,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

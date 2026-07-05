import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(LucideIcons.chevronLeft300), onPressed: () => setState(() => _year--)),
              Text('$_year', style: Theme.of(context).textTheme.titleMedium),
              IconButton(icon: const Icon(LucideIcons.chevronRight300), onPressed: () => setState(() => _year++)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 2,
              children: [
                for (var m = 1; m <= 12; m++)
                  TextButton(
                    onPressed: () => widget.onSelected(YearMonth(_year, m)),
                    child: Text(_monthAbbrev(m)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _monthAbbrev(int month) => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][month - 1];

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';

/// One donut slice: a color, its (absolute) value and identity for tap-through.
class DonutSlice {
  const DonutSlice({required this.color, required this.value, this.drillable = false});

  final Color color;
  final double value;
  final bool drillable;
}

/// Reusable donut (extracted from the old analytics pie). Optional [center]
/// widget sits in the hole; [onTap] fires with the touched slice index when
/// that slice is [DonutSlice.drillable].
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices, this.center, this.onTap, this.size = 240});

  final List<DonutSlice> slices;
  final Widget? center;
  final void Function(int index)? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              centerSpaceRadius: 60,
              sectionsSpace: 5,
              sections: [
                for (var i = 0; i < slices.length; i++)
                  PieChartSectionData(
                    value: slices[i].value.abs(),
                    color: slices[i].color,
                    title: '',
                    radius: 20,
                  ),
              ],
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (onTap == null || !event.isInterestedForInteractions) return;
                  final index = response?.touchedSection?.touchedSectionIndex;
                  if (index == null || index < 0 || index >= slices.length) return;
                  if (slices[index].drillable) onTap!(index);
                },
              ),
            ),
          ),
          ?center,
        ],
      ),
    );
  }
}

/// Legend/list row shared by donut sections: color dot, label, amount and an
/// optional drill chevron.
class LegendRow extends StatelessWidget {
  const LegendRow({
    super.key,
    required this.color,
    required this.label,
    required this.trailing,
    this.canDrill = false,
    this.onTap,
  });

  final Color color;
  final String label;
  final String trailing;
  final bool canDrill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: canDrill ? onTap : null,
      borderRadius: BorderRadius.circular(AppDimens.radiusButton),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.smMd, horizontal: AppSpacing.xs),
        child: Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: AppSpacing.smMd),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
            Text(
              trailing,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge!
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            if (canDrill) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(LucideIcons.chevronRight300, size: 16, color: colors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../app_card.dart';
import '../thin_progress_bar.dart';

/// One donut slice: a color, its (absolute) value and identity for tap-through.
class DonutSlice {
  const DonutSlice({required this.color, required this.value, this.drillable = false});

  final Color color;
  final double value;
  final bool drillable;
}

/// Reusable donut (extracted from the old analytics pie). Optional [center]
/// widget sits in the hole; [onTap] fires with the touched slice index when
/// that slice is [DonutSlice.drillable] (i.e. opens a detail).
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
          // Own layer for the (animated) chart painting (BL-070).
          RepaintBoundary(
            child: PieChart(
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
          ),
          ?center,
        ],
      ),
    );
  }
}

/// Breakdown row shared by the donut sections: color dot, label and amount on
/// the first line, a proportional bar in the slice color, then an optional
/// [meta] line (e.g. transaction count) and the [share] as a percentage. A
/// chevron shows when [onTap] is set (opens the item's detail).
class BreakdownRow extends StatelessWidget {
  const BreakdownRow({
    super.key,
    required this.color,
    required this.label,
    required this.amount,
    required this.share,
    this.meta,
    this.onTap,
  });

  final Color color;
  final String label;
  final String amount;

  /// 0..1 of the breakdown total; drives the bar and the percentage.
  final double share;

  /// Optional muted line under the bar (count, savings…).
  final String? meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall!.copyWith(color: colors.textMuted);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.radiusButton),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.smMd, horizontal: AppSpacing.xs),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: AppSpacing.smMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(label, style: text.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        amount,
                        style: text.labelLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ThinProgressBar(value: share, fillColor: color, height: 4),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(meta ?? '', style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        '${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)}%',
                        style: muted.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(LucideIcons.chevronRight300, size: 16, color: colors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

/// Card holding a list of [BreakdownRow]s separated by hairlines, with an
/// optional uppercase [title].
class BreakdownCard extends StatelessWidget {
  const BreakdownCard({super.key, required this.rows, this.title});

  final List<Widget> rows;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.smMd, AppSpacing.sm, AppSpacing.smMd, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
              child: Text(title!.toUpperCase(), style: appHeaderStyle(colors)),
            ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: colors.borderSoft),
            rows[i],
          ],
        ],
      ),
    );
  }
}

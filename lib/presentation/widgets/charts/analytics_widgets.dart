import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';

/// Locale-aware money format (C1). Kept as `formatAmount` so the many analytics
/// call sites stay unchanged; delegates to the single [formatMoney] helper.
String formatAmount(int cents, String currency) => formatMoney(cents, currency);

/// A single KPI: small uppercase label + large Clash value, optional accent color.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smMd),
      decoration: BoxDecoration(
        color: colors.mutedFill(0.3),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: appHeaderStyle(colors)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: appDisplay(colors, fontSize: 22, color: color ?? colors.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Responsive 2-column grid of [KpiTile]s.
class KpiTileGrid extends StatelessWidget {
  const KpiTileGrid({super.key, required this.tiles});

  final List<KpiTile> tiles;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.smMd,
      crossAxisSpacing: AppSpacing.smMd,
      childAspectRatio: 2.4,
      children: tiles,
    );
  }
}

/// A ranked bar list: label, value text and a proportional fill.
class RankedList extends StatelessWidget {
  const RankedList({super.key, required this.entries});

  final List<RankedEntry> entries;

  @override
  Widget build(BuildContext context) {
    final max = entries.fold<int>(1, (m, e) => e.amountCents.abs() > m ? e.amountCents.abs() : m);
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.label, style: Theme.of(context).textTheme.labelLarge)),
                    Text(
                      e.trailing,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall!
                          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                  child: LinearProgressIndicator(
                    value: (e.amountCents.abs() / max).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: context.appColors.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(e.color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class RankedEntry {
  const RankedEntry({required this.label, required this.trailing, required this.amountCents, required this.color});
  final String label;
  final String trailing;
  final int amountCents;
  final Color color;
}

/// Simple bar chart of monthly values (fl_chart). [labels] align with [values].
class MonthlyBars extends StatelessWidget {
  const MonthlyBars({super.key, required this.values, required this.labels, this.color, this.height = 160});

  final List<int> values;
  final List<String> labels;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final barColor = color ?? colors.accent;
    final maxVal = values.fold<int>(1, (m, v) => v.abs() > m ? v.abs() : m);
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal.toDouble(),
          minY: values.any((v) => v < 0) ? -maxVal.toDouble() : 0,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(labels[i], style: TextStyle(fontSize: 9, color: colors.textMuted)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: values[i].toDouble(),
                  color: barColor,
                  width: 10,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Line chart of one or two series over months (fl_chart).
class TrendLines extends StatelessWidget {
  const TrendLines({super.key, required this.series, this.height = 160});

  /// Each series: a color and its per-point values (all series share the x axis).
  final List<({Color color, List<double> values})> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final all = series.expand((s) => s.values);
    final maxY = all.isEmpty ? 1.0 : all.reduce((a, b) => a > b ? a : b);
    final minY = all.isEmpty ? 0.0 : all.reduce((a, b) => a < b ? a : b);
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY < 0 ? minY : 0,
          maxY: maxY <= 0 ? 1 : maxY,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineBarsData: [
            for (final s in series)
              LineChartBarData(
                spots: [for (var i = 0; i < s.values.length; i++) FlSpot(i.toDouble(), s.values[i])],
                isCurved: true,
                color: s.color,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
              ),
          ],
        ),
      ),
    );
  }
}

/// Circular gauge showing a 0..1 fraction as a labelled ring.
class RingGauge extends StatelessWidget {
  const RingGauge({super.key, required this.fraction, required this.label, this.color});

  final double fraction;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final ringColor = color ?? colors.accent;
    return Row(
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CircularProgressIndicator(
                  value: fraction.clamp(0.0, 1.0),
                  strokeWidth: 10,
                  backgroundColor: colors.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation(ringColor),
                ),
              ),
              Text('${(fraction * 100).round()}%', style: appDisplay(colors, fontSize: 20)),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}

/// A month calendar heatmap: 7-column grid, cells tinted by intensity (0..1).
class CalendarHeatmap extends StatelessWidget {
  const CalendarHeatmap({super.key, required this.month, required this.intensityByDay, this.color});

  final DateTime month;
  final Map<int, double> intensityByDay; // dayOfMonth → 0..1
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final base = color ?? colors.accent;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1=Mon
    final cells = <Widget>[];
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final intensity = intensityByDay[d] ?? 0;
      cells.add(
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: intensity <= 0 ? colors.surfaceAlt : base.withValues(alpha: 0.15 + 0.85 * intensity),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      children: cells,
    );
  }
}

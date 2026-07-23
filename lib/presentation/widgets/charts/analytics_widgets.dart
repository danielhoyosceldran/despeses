import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';

/// Locale-aware money format (C1). Kept as `formatAmount` so the many analytics
/// call sites stay unchanged; delegates to the single [formatMoney] helper.
String formatAmount(int cents, String currency) => formatMoney(cents, currency);

/// Small "i" icon button that opens [showStatInfoSheet] with a beginner-friendly
/// explanation of the chart/stat it's attached to.
class StatInfoButton extends StatelessWidget {
  const StatInfoButton({super.key, required this.title, required this.body, this.example});

  final String title;
  final String body;
  final Widget? example;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(LucideIcons.info300, size: 18, color: context.appColors.textMuted),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: title,
      onPressed: () => showStatInfoSheet(context, title: title, body: body, example: example),
    );
  }
}

/// Bottom sheet explaining a single statistic in plain language, with an
/// optional [example] widget (e.g. a sample chart) illustrating it.
void showStatInfoSheet(BuildContext context, {required String title, required String body, Widget? example}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final colors = ctx.appColors;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.smMd),
              Text(body, style: Theme.of(ctx).textTheme.bodyMedium!.copyWith(color: colors.text)),
              if (example != null) ...[
                const SizedBox(height: AppSpacing.lg),
                example,
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// A single KPI: small uppercase label + large Clash value, optional accent color.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.color, this.infoBody});

  final String label;
  final String value;
  final Color? color;

  /// Beginner-friendly explanation shown in a bottom sheet via the info button.
  final String? infoBody;

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
          Row(
            children: [
              Expanded(
                child: Text(label.toUpperCase(), style: appHeaderStyle(colors), overflow: TextOverflow.ellipsis),
              ),
              if (infoBody != null) StatInfoButton(title: label, body: infoBody!),
            ],
          ),
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
///
/// Built from paired [Row]s wrapped in [IntrinsicHeight] (not a `GridView` with
/// a fixed `childAspectRatio`) so each row's height follows its content. A fixed
/// aspect ratio produced cells shorter than the tile content at phone widths and
/// clipped the value with a bottom overflow; this adapts to any width and text
/// scale, and keeps both tiles in a row the same height.
class KpiTileGrid extends StatelessWidget {
  const KpiTileGrid({super.key, required this.tiles});

  final List<KpiTile> tiles;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.smMd;
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final right = i + 1 < tiles.length ? tiles[i + 1] : null;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: spacing));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: spacing),
              // Keep a half-width gap so a lone trailing tile stays column-aligned.
              Expanded(child: right ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
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
    final all = series.expand((s) => s.values).toList();
    final pointCount = series.fold<int>(0, (m, s) => s.values.length > m ? s.values.length : m);
    final dataMax = all.isEmpty ? 1.0 : all.reduce((a, b) => a > b ? a : b);
    final dataMin = all.isEmpty ? 0.0 : all.reduce((a, b) => a < b ? a : b);
    final lo = dataMin < 0 ? dataMin : 0.0;
    final hi = dataMax <= 0 ? 1.0 : dataMax;
    // Vertical headroom so the curve (which can bow past its points) and the
    // 2.5px stroke stay inside the box instead of being clipped at top/bottom.
    final headroom = (hi - lo) == 0 ? 1.0 : (hi - lo) * 0.12;
    // Horizontal margin so the first/last points and their stroke width are not
    // sliced at the left/right edges.
    final lastX = pointCount <= 1 ? 1.0 : (pointCount - 1).toDouble();
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: -0.3,
          maxX: lastX + 0.3,
          minY: lo - headroom,
          maxY: hi + headroom,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            for (final s in series)
              LineChartBarData(
                spots: [for (var i = 0; i < s.values.length; i++) FlSpot(i.toDouble(), s.values[i])],
                isCurved: true,
                // Stop the spline from bowing past data extremes, which pushed
                // steep segments outside the box and got clipped.
                preventCurveOverShooting: true,
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
          // No clip: the indicator stroke is kept inside via strokeAlign, but
          // guard against the Stack's default hardEdge clip flattening the ring.
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CircularProgressIndicator(
                  value: fraction.clamp(0.0, 1.0),
                  strokeWidth: 10,
                  // Draw the 10px stroke *inside* the 96px box. With the default
                  // (center) align the stroke bleeds 5px past the box on every
                  // side and gets clipped, flattening the ring's edges.
                  strokeAlign: BorderSide.strokeAlignInside,
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

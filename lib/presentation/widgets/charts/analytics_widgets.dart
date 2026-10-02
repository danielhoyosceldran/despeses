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

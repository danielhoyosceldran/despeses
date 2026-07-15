import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/charts/analytics_widgets.dart';
import '../../widgets/error_retry.dart';
import 'analytics_data_providers.dart';

/// Shared helpers -----------------------------------------------------------

const _monthAbbr = ['', 'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

String _monthLabel(DateTime m) => _monthAbbr[m.month];

Widget _loading() => const Center(child: CircularProgressIndicator());

ErrorRetry _sectionError(VoidCallback onRetry) =>
    ErrorRetry(onRetry: onRetry, message: 'Could not load this section.');

/// A titled card wrapper for a single statistic (ref id + title + body).
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.textMuted)),
          ],
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// Rolling-window selector [6M][12M][24M] used by time-series sections.
class WindowSelector extends StatelessWidget {
  const WindowSelector({super.key, required this.window, required this.onWindow});

  final int window;
  final ValueChanged<int> onWindow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 6, label: Text('6M')),
          ButtonSegment(value: 12, label: Text('12M')),
          ButtonSegment(value: 24, label: Text('24M')),
        ],
        selected: {window},
        onSelectionChanged: (s) => onWindow(s.first),
      ),
    );
  }
}

String _pct(double? f) => f == null ? '—' : '${(f * 100).toStringAsFixed(1)}%';
String _signedPct(double? f) => f == null ? '—' : '${f >= 0 ? '+' : ''}${(f * 100).toStringAsFixed(1)}%';

/// Health -------------------------------------------------------------------

class HealthSection extends ConsumerWidget {
  const HealthSection({super.key, required this.month, required this.currency});

  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (month: month, currency: currency);
    return ref.watch(healthSectionProvider(args)).when(
          loading: _loading,
          error: (_, _) => _sectionError(() => ref.invalidate(healthSectionProvider(args))),
          data: (value) {
            final (h, topLabel) = value;
            final colors = context.appColors;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                KpiTileGrid(tiles: [
                  KpiTile(label: 'Savings rate', value: _pct(h.savingsRate), color: colors.text),
                  KpiTile(label: 'vs 3M avg', value: _signedPct(h.spendVsAverage)),
                  KpiTile(label: 'Top category', value: topLabel ?? '—'),
                  KpiTile(
                    label: 'Budgets at risk',
                    value: '${h.budgetsAtRisk}',
                    color: h.budgetsAtRisk > 0 ? context.semanticColors.over : null,
                  ),
                  KpiTile(label: 'Projection', value: formatAmount(h.projectedSpend, currency)),
                  KpiTile(label: 'No-spend streak', value: '${h.noSpendStreak}d'),
                ]),
                const SizedBox(height: AppSpacing.md),
                StatCard(
                  title: 'This month vs last (burn-up)',
                  subtitle: 'A1.4',
                  child: _BurnUp(month: month, currency: currency),
                ),
              ],
            );
          },
        );
  }
}

class _BurnUp extends ConsumerWidget {
  const _BurnUp({required this.month, required this.currency});
  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (month: month, currency: currency);
    return ref.watch(burnUpProvider(args)).when(
          loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (_, _) => SizedBox(
              height: 160, child: _sectionError(() => ref.invalidate(burnUpProvider(args)))),
          data: (data) {
            final colors = context.appColors;
            return TrendLines(series: [
              (color: colors.accent, values: [for (final p in data.current) (p.$2 / 100)]),
              (color: colors.textMuted, values: [for (final p in data.previous) (p.$2 / 100)]),
            ]);
          },
        );
  }
}

/// Trend --------------------------------------------------------------------

class TrendSection extends ConsumerWidget {
  const TrendSection({
    super.key,
    required this.month,
    required this.currency,
    required this.window,
    required this.onWindow,
  });

  final DateTime month;
  final String currency;
  final int window;
  final ValueChanged<int> onWindow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (month: month, currency: currency, window: window);
    return Column(
      children: [
        WindowSelector(window: window, onWindow: onWindow),
        Expanded(
          child: ref.watch(trendSectionProvider(args)).when(
                loading: _loading,
                error: (_, _) => _sectionError(() => ref.invalidate(trendSectionProvider(args))),
                data: (d) {
                  final colors = context.appColors;
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      Row(children: [
                        Expanded(child: KpiTile(label: 'MoM', value: _signedPct(d.mom))),
                        const SizedBox(width: AppSpacing.smMd),
                        Expanded(child: KpiTile(label: 'YoY', value: _signedPct(d.yoy))),
                      ]),
                      const SizedBox(height: AppSpacing.md),
                      StatCard(
                        title: 'Monthly spend',
                        subtitle: 'A1.1 · A1.2 (3M avg)',
                        child: Column(children: [
                          MonthlyBars(
                            values: [for (final t in d.totals) t.$2],
                            labels: [for (final t in d.totals) _monthLabel(t.$1)],
                            color: colors.accent,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TrendLines(series: [
                            (color: context.semanticColors.savings, values: [for (final a in d.movingAvg) a.$2 / 100])
                          ], height: 60),
                        ]),
                      ),
                      StatCard(
                        title: 'Average by weekday',
                        subtitle: 'A1.6',
                        child: MonthlyBars(
                          values: [for (var w = 1; w <= 7; w++) (d.weekday[w] ?? 0).round()],
                          labels: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                          color: colors.textMuted,
                        ),
                      ),
                      StatCard(
                        title: 'Calendar heatmap',
                        subtitle: 'A1.7',
                        child: _HeatmapView(month: month, heat: d.heat),
                      ),
                    ],
                  );
                },
              ),
        ),
      ],
    );
  }
}

class _HeatmapView extends StatelessWidget {
  const _HeatmapView({required this.month, required this.heat});
  final DateTime month;
  final Map<int, int> heat;

  @override
  Widget build(BuildContext context) {
    final max = heat.values.fold<int>(1, (m, v) => v.abs() > m ? v.abs() : m);
    return CalendarHeatmap(
      month: month,
      intensityByDay: {for (final e in heat.entries) e.key: (e.value.abs() / max).clamp(0.0, 1.0)},
    );
  }
}

/// Cash flow ----------------------------------------------------------------

class CashflowSection extends ConsumerWidget {
  const CashflowSection({
    super.key,
    required this.month,
    required this.currency,
    required this.window,
    required this.onWindow,
  });

  final DateTime month;
  final String currency;
  final int window;
  final ValueChanged<int> onWindow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (month: month, currency: currency, window: window);
    return Column(
      children: [
        WindowSelector(window: window, onWindow: onWindow),
        Expanded(
          child: ref.watch(cashflowSectionProvider(args)).when(
                loading: _loading,
                error: (_, _) => _sectionError(() => ref.invalidate(cashflowSectionProvider(args))),
                data: (d) {
                  final colors = context.appColors;
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      StatCard(
                        title: 'Net cash-flow',
                        subtitle: 'A2.1 (income − spend − savings)',
                        child: MonthlyBars(
                          values: [for (final m in d.months) m.net],
                          labels: [for (final m in d.months) _monthLabel(m.month)],
                          color: colors.accent,
                        ),
                      ),
                      StatCard(
                        title: 'Savings rate',
                        subtitle: 'A2.2 (savings / income, this month)',
                        child: RingGauge(
                          fraction: d.months.isEmpty ? 0 : d.months.last.savingsRate,
                          label: 'Of income kept as savings this month',
                          color: context.semanticColors.savings,
                        ),
                      ),
                      StatCard(
                        title: 'Cumulative balance',
                        subtitle: 'A2.3',
                        child: TrendLines(series: [
                          (color: colors.accent, values: [for (final b in d.balance) b.$2 / 100])
                        ]),
                      ),
                      StatCard(
                        title: 'Savings — cumulative',
                        subtitle: 'Ahorro acumulado',
                        child: TrendLines(series: [
                          (color: context.semanticColors.savings, values: [for (final s in d.savings) s.$2 / 100])
                        ]),
                      ),
                    ],
                  );
                },
              ),
        ),
      ],
    );
  }
}

/// Payment ------------------------------------------------------------------

class PaymentSection extends ConsumerWidget {
  const PaymentSection({super.key, required this.month, required this.currency});

  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (month: month, currency: currency);
    return ref.watch(paymentSectionProvider(args)).when(
          loading: _loading,
          error: (_, _) => _sectionError(() => ref.invalidate(paymentSectionProvider(args))),
          data: (d) {
            if (d.byMethod.isEmpty) return const _Empty('No payment data.');
            final entries = d.byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                StatCard(
                  title: 'Spend by payment method',
                  subtitle: 'A5.1',
                  child: RankedList(entries: [
                    for (var i = 0; i < entries.length; i++)
                      RankedEntry(
                        label: d.labels[entries[i].key] ?? '—',
                        trailing: formatAmount(entries[i].value, currency),
                        amountCents: entries[i].value,
                        color: AppDataColors.cycle[i % AppDataColors.cycle.length],
                      ),
                  ]),
                ),
              ],
            );
          },
        );
  }
}

/// Behavior -----------------------------------------------------------------

class BehaviorSection extends ConsumerWidget {
  const BehaviorSection({super.key, required this.month, required this.currency});

  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (month: month, currency: currency);
    return ref.watch(behaviorSectionProvider(args)).when(
          loading: _loading,
          error: (_, _) => _sectionError(() => ref.invalidate(behaviorSectionProvider(args))),
          data: (d) {
            final colors = context.appColors;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                KpiTileGrid(tiles: [
                  KpiTile(label: 'Transactions', value: '${d.stats.count}'),
                  KpiTile(label: 'Mean ticket', value: formatAmount(d.stats.mean.round(), currency)),
                  KpiTile(label: 'Median ticket', value: formatAmount(d.stats.median.round(), currency)),
                  KpiTile(label: 'Max ticket', value: formatAmount(d.stats.max, currency)),
                ]),
                const SizedBox(height: AppSpacing.md),
                StatCard(
                  title: 'Amount distribution',
                  subtitle: 'A8.3',
                  child: MonthlyBars(
                    values: d.histogram,
                    labels: const ['<5', '<10', '<25', '<50', '<100', '100+'],
                    color: colors.accent,
                  ),
                ),
                StatCard(
                  title: 'Ant spend',
                  subtitle: 'A8.5 (micro-transactions < 5 $currency)',
                  child: Text(
                    '${formatAmount(d.ant.total, currency)}  ·  ${d.ant.count} txns',
                    style: appDisplay(colors, fontSize: 20),
                  ),
                ),
                StatCard(
                  title: 'Refunds',
                  subtitle: 'A8.7',
                  child: RingGauge(
                    fraction: d.refundRatio,
                    label: 'Refunded vs gross spend',
                    color: context.semanticColors.refund,
                  ),
                ),
              ],
            );
          },
        );
  }
}

/// Quality ------------------------------------------------------------------

class QualitySection extends ConsumerWidget {
  const QualitySection({super.key, required this.month, required this.currency});

  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (month: month, currency: currency);
    return ref.watch(qualitySectionProvider(args)).when(
          loading: _loading,
          error: (_, _) => _sectionError(() => ref.invalidate(qualitySectionProvider(args))),
          data: (gap) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                StatCard(
                  title: 'Tag coverage gap',
                  subtitle: 'A4.3',
                  child: RingGauge(
                    fraction: gap,
                    label: 'Of transactions have no tag',
                    color: context.semanticColors.over,
                  ),
                ),
              ],
            );
          },
        );
  }
}

/// Budgets ------------------------------------------------------------------

class BudgetsSection extends ConsumerWidget {
  const BudgetsSection({super.key, required this.month, required this.currency});

  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (month: month, currency: currency);
    return ref.watch(budgetSectionProvider(args)).when(
          loading: _loading,
          error: (_, _) => _sectionError(() => ref.invalidate(budgetSectionProvider(args))),
          data: (rows) {
            if (rows.isEmpty) return const _Empty('No active budgets.');
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                for (final r in rows)
                  StatCard(
                    title: r.name,
                    subtitle: 'A7.1–A7.3',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                              child: LinearProgressIndicator(
                                value: r.spentFraction.clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor: context.appColors.surfaceAlt,
                                valueColor: AlwaysStoppedAnimation(
                                  r.overPace ? context.semanticColors.over : context.semanticColors.savings,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.smMd),
                          Text('${formatAmount(r.spent, currency)} / ${formatAmount(r.limit, currency)}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ]),
                        if (r.projected != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Projected close: ${formatAmount(r.projected!, currency)}${r.overPace ? '  ⚠ over pace' : ''}',
                            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                  color: r.overPace ? context.semanticColors.over : context.appColors.textMuted,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        );
  }
}

/// Events -------------------------------------------------------------------

class EventsSection extends ConsumerStatefulWidget {
  const EventsSection({super.key, required this.currency});
  final String currency;

  @override
  ConsumerState<EventsSection> createState() => _EventsSectionState();
}

class _EventsSectionState extends ConsumerState<EventsSection> {
  String? _selectedEventId;

  @override
  Widget build(BuildContext context) {
    return ref.watch(eventListProvider).when(
          loading: _loading,
          error: (_, _) => _sectionError(() => ref.invalidate(eventListProvider)),
          data: (events) {
            if (events.isEmpty) return const _Empty('No events yet.');
            _selectedEventId ??= events.first.id;
            final selected = events.firstWhere((e) => e.id == _selectedEventId);
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedEventId,
                  decoration: const InputDecoration(labelText: 'Event'),
                  items: [for (final e in events) DropdownMenuItem(value: e.id, child: Text(e.name))],
                  onChanged: (v) => setState(() => _selectedEventId = v),
                ),
                const SizedBox(height: AppSpacing.md),
                _EventBody(
                  key: ValueKey(_selectedEventId),
                  eventId: selected.id,
                  startsAt: selected.startsAt,
                  endsAt: selected.endsAt,
                  currency: widget.currency,
                ),
              ],
            );
          },
        );
  }
}

class _EventBody extends ConsumerWidget {
  const _EventBody({
    super.key,
    required this.eventId,
    required this.startsAt,
    required this.endsAt,
    required this.currency,
  });

  final String eventId;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (eventId: eventId, startsAt: startsAt, endsAt: endsAt, currency: currency);
    return ref.watch(eventSectionProvider(args)).when(
          loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          error: (_, _) => SizedBox(
              height: 120, child: _sectionError(() => ref.invalidate(eventSectionProvider(args)))),
          data: (d) {
            final colors = context.appColors;
            return Column(
              children: [
                Row(children: [
                  Expanded(child: KpiTile(label: 'Total cost', value: formatAmount(d.total, currency))),
                  const SizedBox(width: AppSpacing.smMd),
                  Expanded(
                    child: KpiTile(
                      label: 'Cost / day',
                      value: d.perDay == null ? '—' : formatAmount(d.perDay!.round(), currency),
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                StatCard(
                  title: 'Spend timeline',
                  subtitle: 'A6.5',
                  child: TrendLines(series: [
                    (color: colors.accent, values: [for (final p in d.timeline) p.$2 / 100])
                  ]),
                ),
                if (d.outOfRange > 0)
                  StatCard(
                    title: 'Out-of-range transactions',
                    subtitle: 'A6.6',
                    child: Text('${d.outOfRange} transaction(s) dated outside the event period.',
                        style: TextStyle(color: context.semanticColors.over)),
                  ),
              ],
            );
          },
        );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: Text(text)));
}

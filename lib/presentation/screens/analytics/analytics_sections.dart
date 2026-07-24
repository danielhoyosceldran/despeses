import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/charts/analytics_widgets.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_retry.dart';
import 'analytics_data_providers.dart';

/// Shared helpers -----------------------------------------------------------

const _monthAbbr = ['', 'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

String _monthLabel(DateTime m) => _monthAbbr[m.month];

Widget _loading() => const Center(child: CircularProgressIndicator());

ErrorRetry _sectionError(WidgetRef ref, VoidCallback onRetry) {
  final t = ref.read(translationsProvider).asData?.value;
  return ErrorRetry(
    onRetry: onRetry,
    message: t?.t('analytics.error_section') ?? 'Could not load this section.',
    retryLabel: t?.t('common.retry') ?? 'Retry',
  );
}

/// A titled card wrapper for a single statistic (ref id + title + body).
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.title, required this.child, this.subtitle, this.infoBody, this.infoExample});

  final String title;
  final String? subtitle;
  final Widget child;

  /// Beginner-friendly explanation shown in a bottom sheet via an info button
  /// next to the title. Omit to hide the button (e.g. per-budget cards).
  final String? infoBody;

  /// Optional sample widget (e.g. a mini chart) shown below [infoBody] in the sheet.
  final Widget? infoExample;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.labelLarge)),
              if (infoBody != null) StatInfoButton(title: title, body: infoBody!, example: infoExample),
            ],
          ),
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
    final t = ref.watch(translationsProvider).asData?.value;
    return ref.watch(healthSectionProvider(args)).when(
          loading: _loading,
          error: (_, _) => _sectionError(ref, () => ref.invalidate(healthSectionProvider(args))),
          data: (value) {
            final (h, topLabel) = value;
            final colors = context.appColors;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                KpiTileGrid(tiles: [
                  KpiTile(
                    label: t?.t('analytics.kpi_savings_rate') ?? 'Savings rate',
                    value: _pct(h.savingsRate),
                    color: colors.text,
                    infoBody: t?.t('analytics_info.savings_rate'),
                  ),
                  KpiTile(
                    label: t?.t('analytics.kpi_vs_3m_avg') ?? 'vs 3M avg',
                    value: _signedPct(h.spendVsAverage),
                    infoBody: t?.t('analytics_info.vs_3m_avg'),
                  ),
                  KpiTile(
                    label: t?.t('analytics.kpi_top_category') ?? 'Top category',
                    value: topLabel ?? '—',
                    infoBody: t?.t('analytics_info.top_category'),
                  ),
                  KpiTile(
                    label: t?.t('analytics.kpi_budgets_at_risk') ?? 'Budgets at risk',
                    value: '${h.budgetsAtRisk}',
                    color: h.budgetsAtRisk > 0 ? context.semanticColors.over : null,
                    infoBody: t?.t('analytics_info.budgets_at_risk'),
                  ),
                  KpiTile(
                    label: t?.t('analytics.kpi_projection') ?? 'Projection',
                    value: formatAmount(h.projectedSpend, currency),
                    infoBody: t?.t('analytics_info.projection'),
                  ),
                  KpiTile(
                    label: t?.t('analytics.kpi_no_spend_streak') ?? 'No-spend streak',
                    value: '${h.noSpendStreak}d',
                    infoBody: t?.t('analytics_info.no_spend_streak'),
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                StatCard(
                  title: t?.t('analytics.stat_burnup') ?? 'This month vs last (burn-up)',
                  infoBody: t?.t('analytics_info.burnup'),
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
              height: 160, child: _sectionError(ref, () => ref.invalidate(burnUpProvider(args)))),
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
    final t = ref.watch(translationsProvider).asData?.value;
    return Column(
      children: [
        WindowSelector(window: window, onWindow: onWindow),
        Expanded(
          child: ref.watch(trendSectionProvider(args)).when(
                loading: _loading,
                error: (_, _) => _sectionError(ref, () => ref.invalidate(trendSectionProvider(args))),
                data: (d) {
                  final colors = context.appColors;
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      Row(children: [
                        Expanded(
                            child: KpiTile(
                          label: t?.t('analytics.kpi_mom') ?? 'MoM',
                          value: _signedPct(d.mom),
                          infoBody: t?.t('analytics_info.mom'),
                        )),
                        const SizedBox(width: AppSpacing.smMd),
                        Expanded(
                            child: KpiTile(
                          label: t?.t('analytics.kpi_yoy') ?? 'YoY',
                          value: _signedPct(d.yoy),
                          infoBody: t?.t('analytics_info.yoy'),
                        )),
                      ]),
                      const SizedBox(height: AppSpacing.md),
                      StatCard(
                        title: t?.t('analytics.stat_monthly_spend') ?? 'Monthly spend',
                        subtitle: t?.t('analytics.stat_3month_avg') ?? '3-month average',
                        infoBody: t?.t('analytics_info.monthly_spend'),
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
                        title: t?.t('analytics.stat_avg_weekday') ?? 'Average by weekday',
                        infoBody: t?.t('analytics_info.avg_weekday'),
                        child: MonthlyBars(
                          values: [for (var w = 1; w <= 7; w++) (d.weekday[w] ?? 0).round()],
                          labels: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                          color: colors.textMuted,
                        ),
                      ),
                      StatCard(
                        title: t?.t('analytics.stat_calendar_heatmap') ?? 'Calendar heatmap',
                        infoBody: t?.t('analytics_info.calendar_heatmap'),
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
    final t = ref.watch(translationsProvider).asData?.value;
    return Column(
      children: [
        WindowSelector(window: window, onWindow: onWindow),
        Expanded(
          child: ref.watch(cashflowSectionProvider(args)).when(
                loading: _loading,
                error: (_, _) => _sectionError(ref, () => ref.invalidate(cashflowSectionProvider(args))),
                data: (d) {
                  final colors = context.appColors;
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      StatCard(
                        title: t?.t('analytics.stat_net_cashflow') ?? 'Net cash-flow',
                        subtitle: t?.t('analytics.stat_net_cashflow_sub') ?? 'income − spend − savings',
                        infoBody: t?.t('analytics_info.net_cashflow'),
                        child: MonthlyBars(
                          values: [for (final m in d.months) m.net],
                          labels: [for (final m in d.months) _monthLabel(m.month)],
                          color: colors.accent,
                        ),
                      ),
                      StatCard(
                        title: t?.t('analytics.stat_savings_rate') ?? 'Savings rate',
                        subtitle: t?.t('analytics.stat_savings_rate_sub') ?? 'savings / income, this month',
                        infoBody: t?.t('analytics_info.savings_rate'),
                        infoExample: RingGauge(fraction: 0.35, label: t?.t('analytics.ring_savings_kept') ?? 'Of income kept as savings this month'),
                        child: RingGauge(
                          fraction: d.months.isEmpty ? 0 : d.months.last.savingsRate,
                          label: t?.t('analytics.ring_savings_kept') ?? 'Of income kept as savings this month',
                          color: context.semanticColors.savings,
                        ),
                      ),
                      StatCard(
                        title: t?.t('analytics.stat_cumulative_balance') ?? 'Cumulative balance',
                        infoBody: t?.t('analytics_info.cumulative_balance'),
                        child: TrendLines(series: [
                          (color: colors.accent, values: [for (final b in d.balance) b.$2 / 100])
                        ]),
                      ),
                      StatCard(
                        title: t?.t('analytics.stat_savings_cumulative') ?? 'Savings — cumulative',
                        subtitle: t?.t('analytics.stat_savings_cumulative_sub') ?? 'Running total',
                        infoBody: t?.t('analytics_info.savings_cumulative'),
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
    final t = ref.watch(translationsProvider).asData?.value;
    return ref.watch(paymentSectionProvider(args)).when(
          loading: _loading,
          error: (_, _) => _sectionError(ref, () => ref.invalidate(paymentSectionProvider(args))),
          data: (d) {
            if (d.byMethod.isEmpty) return EmptyState(t?.t('analytics.empty_payment') ?? 'No payment data.');
            final entries = d.byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                StatCard(
                  title: t?.t('analytics.stat_spend_by_payment') ?? 'Spend by payment method',
                  infoBody: t?.t('analytics_info.spend_by_payment'),
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
    final t = ref.watch(translationsProvider).asData?.value;
    return ref.watch(behaviorSectionProvider(args)).when(
          loading: _loading,
          error: (_, _) => _sectionError(ref, () => ref.invalidate(behaviorSectionProvider(args))),
          data: (d) {
            final colors = context.appColors;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                KpiTileGrid(tiles: [
                  KpiTile(
                    label: t?.t('analytics.kpi_transactions') ?? 'Transactions',
                    value: '${d.stats.count}',
                    infoBody: t?.t('analytics_info.transactions'),
                  ),
                  KpiTile(
                    label: t?.t('analytics.kpi_mean_ticket') ?? 'Mean ticket',
                    value: formatAmount(d.stats.mean.round(), currency),
                    infoBody: t?.t('analytics_info.mean_ticket'),
                  ),
                  KpiTile(
                    label: t?.t('analytics.kpi_median_ticket') ?? 'Median ticket',
                    value: formatAmount(d.stats.median.round(), currency),
                    infoBody: t?.t('analytics_info.median_ticket'),
                  ),
                  KpiTile(
                    label: t?.t('analytics.kpi_max_ticket') ?? 'Max ticket',
                    value: formatAmount(d.stats.max, currency),
                    infoBody: t?.t('analytics_info.max_ticket'),
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                StatCard(
                  title: t?.t('analytics.stat_amount_distribution') ?? 'Amount distribution',
                  infoBody: t?.t('analytics_info.amount_distribution'),
                  child: MonthlyBars(
                    values: d.histogram,
                    labels: const ['<5', '<10', '<25', '<50', '<100', '100+'],
                    color: colors.accent,
                  ),
                ),
                StatCard(
                  title: t?.t('analytics.stat_ant_spend') ?? 'Ant spend',
                  subtitle: (t?.t('analytics.stat_ant_spend_sub') ?? 'micro-transactions < 5 {{currency}}')
                      .replaceAll('{{currency}}', currency),
                  infoBody: t?.t('analytics_info.ant_spend'),
                  child: Text(
                    '${formatAmount(d.ant.total, currency)}  ·  ${d.ant.count} txns',
                    // appDisplay uses height:1.0, which clips the tall Clash
                    // glyph tops on a standalone line; give the line box room.
                    style: appDisplay(colors, fontSize: 20).copyWith(height: 1.2),
                  ),
                ),
                StatCard(
                  title: t?.t('analytics.stat_refunds') ?? 'Refunds',
                  infoBody: t?.t('analytics_info.refunds'),
                  child: RingGauge(
                    fraction: d.refundRatio,
                    label: t?.t('analytics.ring_refunded') ?? 'Refunded vs gross spend',
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
    final t = ref.watch(translationsProvider).asData?.value;
    return ref.watch(qualitySectionProvider(args)).when(
          loading: _loading,
          error: (_, _) => _sectionError(ref, () => ref.invalidate(qualitySectionProvider(args))),
          data: (gap) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                StatCard(
                  title: t?.t('analytics.stat_tag_coverage_gap') ?? 'Tag coverage gap',
                  infoBody: t?.t('analytics_info.tag_coverage_gap'),
                  child: RingGauge(
                    fraction: gap,
                    label: t?.t('analytics.ring_no_tag') ?? 'Of transactions have no tag',
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
    final t = ref.watch(translationsProvider).asData?.value;
    return ref.watch(budgetSectionProvider(args)).when(
          loading: _loading,
          error: (_, _) => _sectionError(ref, () => ref.invalidate(budgetSectionProvider(args))),
          data: (rows) {
            if (rows.isEmpty) return EmptyState(t?.t('analytics.empty_budgets') ?? 'No active budgets.');
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                for (final r in rows)
                  StatCard(
                    title: r.name,
                    infoBody: t?.t('analytics_info.budgets_progress'),
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
                            '${t?.t('analytics.budget_projected_close') ?? 'Projected close:'} ${formatAmount(r.projected!, currency)}${r.overPace ? '  ${t?.t('analytics.budget_over_pace') ?? '⚠ over pace'}' : ''}',
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
    final t = ref.watch(translationsProvider).asData?.value;
    return ref.watch(eventListProvider).when(
          loading: _loading,
          error: (_, _) => _sectionError(ref, () => ref.invalidate(eventListProvider)),
          data: (events) {
            if (events.isEmpty) return EmptyState(t?.t('analytics.empty_events') ?? 'No events yet.');
            final selected = events.firstWhere((e) => e.id == _selectedEventId, orElse: () => events.first);
            if (selected.id != _selectedEventId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _selectedEventId = selected.id);
              });
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedEventId,
                  decoration: InputDecoration(labelText: t?.t('analytics.event_label') ?? 'Event'),
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
    final t = ref.watch(translationsProvider).asData?.value;
    return ref.watch(eventSectionProvider(args)).when(
          loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          error: (_, _) => SizedBox(
              height: 120, child: _sectionError(ref, () => ref.invalidate(eventSectionProvider(args)))),
          data: (d) {
            final colors = context.appColors;
            return Column(
              children: [
                Row(children: [
                  Expanded(
                      child: KpiTile(
                    label: t?.t('analytics.kpi_total_cost') ?? 'Total cost',
                    value: formatAmount(d.total, currency),
                    infoBody: t?.t('analytics_info.total_cost'),
                  )),
                  const SizedBox(width: AppSpacing.smMd),
                  Expanded(
                    child: KpiTile(
                      label: t?.t('analytics.kpi_cost_per_day') ?? 'Cost / day',
                      value: d.perDay == null ? '—' : formatAmount(d.perDay!.round(), currency),
                      infoBody: t?.t('analytics_info.cost_per_day'),
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.md),
                StatCard(
                  title: t?.t('analytics.stat_spend_timeline') ?? 'Spend timeline',
                  infoBody: t?.t('analytics_info.spend_timeline'),
                  child: TrendLines(series: [
                    (color: colors.accent, values: [for (final p in d.timeline) p.$2 / 100])
                  ]),
                ),
                if (d.outOfRange > 0)
                  StatCard(
                    title: t?.t('analytics.stat_out_of_range') ?? 'Out-of-range transactions',
                    child: Text(
                        (t?.t('analytics.out_of_range_body') ?? '{{count}} transaction(s) dated outside the event period.')
                            .replaceAll('{{count}}', '${d.outOfRange}'),
                        style: TextStyle(color: context.semanticColors.over)),
                  ),
              ],
            );
          },
        );
  }
}

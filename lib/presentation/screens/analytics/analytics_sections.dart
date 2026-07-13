import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/display_name.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/repositories/analytics/analytics_cashflow.dart';
import '../../../domain/repositories/analytics/analytics_dashboard.dart';
import '../../../domain/repositories/analytics/analytics_math.dart';
import '../../../domain/repositories/budget_repository.dart';
import '../../widgets/app_card.dart';
import '../../widgets/charts/analytics_widgets.dart';

/// Shared helpers -----------------------------------------------------------

const _monthAbbr = ['', 'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

String _monthLabel(DateTime m) => _monthAbbr[m.month];

Widget _loading() => const Center(child: CircularProgressIndicator());

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
    return FutureBuilder<(FinancialHealth, String?)>(
      future: _load(ref),
      builder: (context, snap) {
        if (!snap.hasData) return _loading();
        final (h, topLabel) = snap.data!;
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

  Future<(FinancialHealth, String?)> _load(WidgetRef ref) async {
    final health = await ref.read(dashboardAnalyticsProvider).summary(month, currency);
    String? topLabel;
    if (health.topCategoryId != null) {
      final t = await ref.read(translationsProvider.future);
      final cats = await ref.read(referenceDataCacheProvider).categories();
      final matches = cats.where((c) => c.id == health.topCategoryId);
      if (matches.isNotEmpty) {
        final c = matches.first;
        topLabel = displayNameFor(t, name: c.name, isDefault: c.isDefault);
      }
    }
    return (health, topLabel);
  }
}

class _BurnUp extends ConsumerWidget {
  const _BurnUp({required this.month, required this.currency});
  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(timeseriesAnalyticsProvider).burnUp(month, currency),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
        final data = snap.data!;
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
    final range = DateRange.trailingMonths(month, window);
    return Column(
      children: [
        WindowSelector(window: window, onWindow: onWindow),
        Expanded(
          child: FutureBuilder(
            future: _load(ref, range),
            builder: (context, snap) {
              if (!snap.hasData) return _loading();
              final d = snap.data!;
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

  Future<_TrendData> _load(WidgetRef ref, DateRange range) async {
    final ts = ref.read(timeseriesAnalyticsProvider);
    final totals = await ts.monthlyTotals(range, currency);
    final movingAvg = await ts.movingAverage(range, currency);
    final mm = await ts.momYoY(month, currency);
    final weekday = await ts.averageByWeekday(range, currency);
    final heat = await ts.calendarHeat(month, currency);
    return _TrendData(totals, movingAvg, mm.mom.fraction, mm.yoy.fraction, weekday, heat);
  }
}

class _TrendData {
  _TrendData(this.totals, this.movingAvg, this.mom, this.yoy, this.weekday, this.heat);
  final List<(DateTime, int)> totals;
  final List<(DateTime, double)> movingAvg;
  final double? mom;
  final double? yoy;
  final Map<int, double> weekday;
  final Map<int, int> heat;
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
    final range = DateRange.trailingMonths(month, window);
    return Column(
      children: [
        WindowSelector(window: window, onWindow: onWindow),
        Expanded(
          child: FutureBuilder(
            future: _load(ref, range),
            builder: (context, snap) {
              if (!snap.hasData) return _loading();
              final d = snap.data!;
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

  Future<_CashflowData> _load(WidgetRef ref, DateRange range) async {
    final cf = ref.read(cashflowAnalyticsProvider);
    return _CashflowData(
      await cf.monthly(range, currency),
      await cf.cumulativeBalance(range, currency),
      await cf.cumulativeSavings(range, currency),
    );
  }
}

class _CashflowData {
  _CashflowData(this.months, this.balance, this.savings);
  final List<MonthlyCashflow> months;
  final List<(DateTime, int)> balance;
  final List<(DateTime, int)> savings;
}

/// Payment ------------------------------------------------------------------

class PaymentSection extends ConsumerWidget {
  const PaymentSection({super.key, required this.month, required this.currency});

  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: _load(ref),
      builder: (context, snap) {
        if (!snap.hasData) return _loading();
        final d = snap.data!;
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

  Future<_PaymentData> _load(WidgetRef ref) async {
    final by = await ref.read(paymentAnalyticsProvider).byMethod(DateRange.month(month), currency);
    final t = await ref.read(translationsProvider.future);
    final methods = await ref.read(referenceDataCacheProvider).paymentMethods();
    final labels = {for (final m in methods) m.id: displayNameFor(t, name: m.name, isDefault: m.isDefault)};
    return _PaymentData(by, labels);
  }
}

class _PaymentData {
  _PaymentData(this.byMethod, this.labels);
  final Map<String?, int> byMethod;
  final Map<String, String> labels;
}

/// Behavior -----------------------------------------------------------------

class BehaviorSection extends ConsumerWidget {
  const BehaviorSection({super.key, required this.month, required this.currency});

  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = DateRange.month(month);
    return FutureBuilder(
      future: _load(ref, range),
      builder: (context, snap) {
        if (!snap.hasData) return _loading();
        final d = snap.data!;
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

  Future<_BehaviorData> _load(WidgetRef ref, DateRange range) async {
    final b = ref.read(behaviorAnalyticsProvider);
    final stats = await b.ticketStats(range, currency);
    final histogram = await b.histogram(range, currency, const [500, 1000, 2500, 5000, 10000]);
    final ant = await b.antSpend(range, currency, 500);
    final refunds = await b.refunds(range, currency);
    return _BehaviorData(stats, histogram, ant, refunds.ratio);
  }
}

class _BehaviorData {
  _BehaviorData(this.stats, this.histogram, this.ant, this.refundRatio);
  final dynamic stats;
  final List<int> histogram;
  final ({int total, int count}) ant;
  final double refundRatio;
}

/// Quality ------------------------------------------------------------------

class QualitySection extends ConsumerWidget {
  const QualitySection({super.key, required this.month, required this.currency});

  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<double>(
      future: ref.read(tagAnalyticsProvider).coverageGap(DateRange.month(month), currency),
      builder: (context, snap) {
        if (!snap.hasData) return _loading();
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            StatCard(
              title: 'Tag coverage gap',
              subtitle: 'A4.3',
              child: RingGauge(
                fraction: snap.data!,
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
    return FutureBuilder(
      future: _load(ref),
      builder: (context, snap) {
        if (!snap.hasData) return _loading();
        final rows = snap.data!;
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

  Future<List<_BudgetRow>> _load(WidgetRef ref) async {
    final repo = ref.read(budgetRepositoryProvider);
    final analytics = ref.read(budgetAnalyticsProvider);
    final monthKey = monthKeyOf(DateTime(month.year, month.month));
    final active = (await repo.listAll()).where((b) => repo.isActiveForMonth(b, monthKey)).toList();
    final rows = <_BudgetRow>[];
    for (final b in active) {
      final pace = await analytics.pace(b);
      rows.add(_BudgetRow(
        name: b.name,
        spent: pace.spentCents,
        limit: pace.limitCents,
        spentFraction: pace.spentFraction,
        overPace: pace.overPace,
        projected: pace.projectedEndCents,
      ));
    }
    return rows;
  }
}

class _BudgetRow {
  _BudgetRow({
    required this.name,
    required this.spent,
    required this.limit,
    required this.spentFraction,
    required this.overPace,
    required this.projected,
  });
  final String name;
  final int spent;
  final int limit;
  final double spentFraction;
  final bool overPace;
  final int? projected;
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
    return FutureBuilder(
      future: ref.read(referenceDataCacheProvider).events(),
      builder: (context, snap) {
        if (!snap.hasData) return _loading();
        final events = snap.data!;
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
    return FutureBuilder(
      future: _load(ref),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
        final d = snap.data!;
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

  Future<_EventData> _load(WidgetRef ref) async {
    final ev = ref.read(eventAnalyticsProvider);
    final total = await ev.totalCost(eventId: eventId);
    final perDay = await ev.costPerDay(startsAt: startsAt, endsAt: endsAt, eventId: eventId);
    final timeline = await ev.timeline(eventId: eventId);
    final oor = await ev.outOfRange(eventId: eventId, startsAt: startsAt, endsAt: endsAt);
    return _EventData(total, perDay, timeline, oor.length);
  }
}

class _EventData {
  _EventData(this.total, this.perDay, this.timeline, this.outOfRange);
  final int total;
  final double? perDay;
  final List<(DateTime, int)> timeline;
  final int outOfRange;
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: Text(text)));
}

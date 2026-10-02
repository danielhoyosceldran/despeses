import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/charts/analytics_widgets.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_retry.dart';
import 'analytics_data_providers.dart';
import 'analytics_detail.dart';

/// Shared helpers -----------------------------------------------------------

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
                // Savings aren't a cost: shown on their own, only when present.
                if (d.savings > 0) ...[
                  const SizedBox(height: AppSpacing.smMd),
                  Row(children: [
                    Expanded(
                      child: KpiTile(
                        label: t?.t('expenses.type_ahorro') ?? 'Savings',
                        value: formatAmount(d.savings, currency),
                      ),
                    ),
                  ]),
                ],
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
                DetailSectionHeader(
                  t?.t('analytics.transactions') ?? 'Transactions',
                  trailing: '${d.expenses.length}',
                ),
                TransactionsByDay(expenses: d.expenses, translations: t),
              ],
            );
          },
        );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/display_name.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/analytics/analytics_category.dart';
import '../../domain/repositories/analytics/analytics_math.dart';
import '../../domain/repositories/analytics/analytics_tags.dart';
import '../widgets/amount_text.dart';
import '../widgets/app_card.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/charts/analytics_widgets.dart';
import '../widgets/charts/donut_chart.dart';
import 'analytics/analytics_sections.dart';

/// The Analytics sections, in tab-strip order. Category and Tags are the
/// preferred (default) views and come first.
enum AnalyticsSection {
  category,
  tags,
  health,
  trend,
  cashflow,
  payment,
  behavior,
  quality,
  budgets,
  events,
}

extension AnalyticsSectionMeta on AnalyticsSection {
  bool get preferred => this == AnalyticsSection.category || this == AnalyticsSection.tags;

  String labelKey() => switch (this) {
        AnalyticsSection.category => 'analytics.section_category',
        AnalyticsSection.tags => 'analytics.section_tags',
        AnalyticsSection.health => 'analytics.section_health',
        AnalyticsSection.trend => 'analytics.section_trend',
        AnalyticsSection.cashflow => 'analytics.section_cashflow',
        AnalyticsSection.payment => 'analytics.section_payment',
        AnalyticsSection.behavior => 'analytics.section_behavior',
        AnalyticsSection.quality => 'analytics.section_quality',
        AnalyticsSection.budgets => 'analytics.section_budgets',
        AnalyticsSection.events => 'analytics.section_events',
      };

  String fallbackLabel() => switch (this) {
        AnalyticsSection.category => 'Categories',
        AnalyticsSection.tags => 'Tags',
        AnalyticsSection.health => 'Health',
        AnalyticsSection.trend => 'Trend',
        AnalyticsSection.cashflow => 'Cash flow',
        AnalyticsSection.payment => 'Payment',
        AnalyticsSection.behavior => 'Behavior',
        AnalyticsSection.quality => 'Quality',
        AnalyticsSection.budgets => 'Budgets',
        AnalyticsSection.events => 'Events',
      };
}

/// Analytics v2: a sectioned screen navigated by a horizontal tab strip.
/// Month-scoped sections use the [AppTopBar] month pager; time-series sections
/// use a rolling window selector rendered inside the section.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  AnalyticsSection _section = AnalyticsSection.category;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// Drill path for the Category section (empty = roots).
  final List<Category> _breadcrumb = [];

  /// Rolling window (months) for time-series sections.
  int _window = 12;

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _breadcrumb.clear();
    });
  }

  void _selectSection(AnalyticsSection s) {
    setState(() {
      _section = s;
      _breadcrumb.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when returning to the Analytics tab (data may have changed).
    ref.listen(currentTabIndexProvider, (_, next) {
      if (next == 3) setState(() {});
    });
    final translations = ref.watch(translationsProvider).asData?.value;
    final currency = ref.watch(profileStreamProvider).asData?.value.currency ?? 'EUR';

    return Scaffold(
      body: Column(
        children: [
          AppTopBar(month: _month, onChangeMonth: _changeMonth),
          _SectionTabStrip(
            current: _section,
            translations: translations,
            onSelect: _selectSection,
          ),
          Expanded(
            child: _buildSection(currency, translations),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String currency, Translations? translations) {
    switch (_section) {
      case AnalyticsSection.category:
        return _CategorySection(
          month: _month,
          currency: currency,
          breadcrumb: _breadcrumb,
          onDrillInto: (c) => setState(() => _breadcrumb.add(c)),
          onPop: () => setState(() => _breadcrumb.removeLast()),
        );
      case AnalyticsSection.tags:
        return _TagsSection(month: _month, currency: currency);
      case AnalyticsSection.health:
        return HealthSection(month: _month, currency: currency);
      case AnalyticsSection.trend:
        return TrendSection(month: _month, currency: currency, window: _window, onWindow: _setWindow);
      case AnalyticsSection.cashflow:
        return CashflowSection(month: _month, currency: currency, window: _window, onWindow: _setWindow);
      case AnalyticsSection.payment:
        return PaymentSection(month: _month, currency: currency);
      case AnalyticsSection.behavior:
        return BehaviorSection(month: _month, currency: currency);
      case AnalyticsSection.quality:
        return QualitySection(month: _month, currency: currency);
      case AnalyticsSection.budgets:
        return BudgetsSection(month: _month, currency: currency);
      case AnalyticsSection.events:
        return EventsSection(currency: currency);
    }
  }

  void _setWindow(int w) => setState(() => _window = w);
}

class _SectionTabStrip extends StatelessWidget {
  const _SectionTabStrip({required this.current, required this.translations, required this.onSelect});

  final AnalyticsSection current;
  final Translations? translations;
  final ValueChanged<AnalyticsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        children: [
          for (final s in AnalyticsSection.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _Tab(
                label: translations?.t(s.labelKey()) ?? s.fallbackLabel(),
                selected: s == current,
                preferred: s.preferred,
                onTap: () => onSelect(s),
                colors: colors,
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.preferred,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final bool selected;
  final bool preferred;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            border: Border.all(
              color: selected
                  ? colors.accent
                  : (preferred ? context.semanticColors.savings.withValues(alpha: 0.6) : colors.borderSoft),
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (preferred) ...[
                Icon(Icons.star_rounded, size: 13, color: selected ? colors.onAccent : context.semanticColors.savings),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: selected ? colors.onAccent : colors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preferred views: Category + Tags (ported from Analytics v1 onto the v2 engine)
// ---------------------------------------------------------------------------

class _CategorySection extends ConsumerWidget {
  const _CategorySection({
    required this.month,
    required this.currency,
    required this.breadcrumb,
    required this.onDrillInto,
    required this.onPop,
  });

  final DateTime month;
  final String currency;
  final List<Category> breadcrumb;
  final ValueChanged<Category> onDrillInto;
  final VoidCallback onPop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parentId = breadcrumb.isEmpty ? null : breadcrumb.last.id;
    final future = _load(ref, parentId);
    return FutureBuilder<_CategoryData>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!;
        final colors = context.appColors;
        final total = data.slices.fold<int>(0, (s, e) => s + e.amountCents);

        if (data.slices.isEmpty) {
          return _EmptyState(text: ref.read(translationsProvider).asData?.value.t('analytics.empty_category') ?? 'No category data.');
        }

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            AppCard.large(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  if (breadcrumb.isNotEmpty) ...[
                    _BreadcrumbRow(breadcrumb: breadcrumb, translations: data.translations, onPop: onPop),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  DonutChart(
                    slices: [
                      for (var i = 0; i < data.slices.length; i++)
                        DonutSlice(
                          color: AppDataColors.cycle[i % AppDataColors.cycle.length],
                          value: data.slices[i].amountCents.toDouble(),
                          drillable: data.hasChildren[data.slices[i].categoryId] ?? false,
                        ),
                    ],
                    center: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('TOTAL', style: appHeaderStyle(colors)),
                        const SizedBox(height: 2),
                        AmountText(amountCents: total, currency: currency, style: appDisplay(colors, fontSize: 24)),
                      ],
                    ),
                    onTap: (i) {
                      final c = data.categoryById[data.slices[i].categoryId];
                      if (c != null) onDrillInto(c);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < data.slices.length; i++)
              LegendRow(
                color: AppDataColors.cycle[i % AppDataColors.cycle.length],
                label: data.labels[data.slices[i].categoryId] ?? '',
                trailing: formatAmount(data.slices[i].amountCents, currency),
                canDrill: data.hasChildren[data.slices[i].categoryId] ?? false,
                onTap: () {
                  final c = data.categoryById[data.slices[i].categoryId];
                  if (c != null) onDrillInto(c);
                },
              ),
          ],
        );
      },
    );
  }

  Future<_CategoryData> _load(WidgetRef ref, String? parentId) async {
    final analytics = ref.read(categoryAnalyticsProvider);
    final translations = await ref.read(translationsProvider.future);
    final allCategories = await ref.read(referenceDataCacheProvider).categories();
    final slices = await analytics.breakdown(
      DateRange.month(month),
      parentId: parentId,
      type: 'expense',
      currency: currency,
    );
    final byId = {for (final c in allCategories) c.id: c};
    final labels = <String, String>{};
    final hasChildren = <String, bool>{};
    for (final s in slices) {
      final c = byId[s.categoryId];
      if (c == null) continue;
      labels[s.categoryId] = displayNameFor(translations, name: c.name, isDefault: c.isDefault);
      hasChildren[s.categoryId] = allCategories.any((x) => x.parentId == s.categoryId);
    }
    return _CategoryData(slices, labels, hasChildren, byId, translations);
  }
}

class _CategoryData {
  _CategoryData(this.slices, this.labels, this.hasChildren, this.categoryById, this.translations);
  final List<CategorySlice> slices;
  final Map<String, String> labels;
  final Map<String, bool> hasChildren;
  final Map<String, Category> categoryById;
  final Translations translations;
}

class _BreadcrumbRow extends StatelessWidget {
  const _BreadcrumbRow({required this.breadcrumb, required this.translations, required this.onPop});

  final List<Category> breadcrumb;
  final Translations translations;
  final VoidCallback onPop;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Material(
          color: colors.surfaceAlt,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPop,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Icon(LucideIcons.arrowLeft300, size: 18, color: colors.text),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.smMd),
        Expanded(
          child: Text(
            breadcrumb.map((c) => displayNameFor(translations, name: c.name, isDefault: c.isDefault)).join('  ›  '),
            style: Theme.of(context).textTheme.labelLarge,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TagsSection extends ConsumerWidget {
  const _TagsSection({required this.month, required this.currency});

  final DateTime month;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<_TagData>(
      future: _load(ref),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final data = snap.data!;
        final colors = context.appColors;
        if (data.slices.isEmpty) {
          return _EmptyState(text: data.translations.t('analytics.empty_tag'));
        }
        final total = data.slices.fold<int>(0, (s, e) => s + e.amountCents.abs());
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            AppCard.large(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: DonutChart(
                slices: [
                  for (var i = 0; i < data.slices.length; i++)
                    DonutSlice(
                      color: AppDataColors.cycle[i % AppDataColors.cycle.length],
                      value: data.slices[i].amountCents.toDouble(),
                    ),
                ],
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('TAGS', style: appHeaderStyle(colors)),
                    const SizedBox(height: 2),
                    AmountText(amountCents: total, currency: currency, style: appDisplay(colors, fontSize: 22)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < data.slices.length; i++)
              LegendRow(
                color: AppDataColors.cycle[i % AppDataColors.cycle.length],
                label: data.labels[data.slices[i].tagId] ?? '',
                trailing: formatAmount(data.slices[i].amountCents, currency),
              ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                data.translations.t('analytics.tag_disclaimer'),
                style: Theme.of(context).textTheme.bodySmall!.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<_TagData> _load(WidgetRef ref) async {
    final analytics = ref.read(tagAnalyticsProvider);
    final translations = await ref.read(translationsProvider.future);
    final allTags = await ref.read(referenceDataCacheProvider).tags();
    final slices = await analytics.byTag(DateRange.month(month), currency);
    final byId = {for (final t in allTags) t.id: t};
    final labels = {
      for (final s in slices)
        if (byId[s.tagId] != null)
          s.tagId: displayNameFor(translations, name: byId[s.tagId]!.name, isDefault: byId[s.tagId]!.isDefault),
    };
    return _TagData(slices, labels, translations);
  }
}

class _TagData {
  _TagData(this.slices, this.labels, this.translations);
  final List<TagSlice> slices;
  final Map<String, String> labels;
  final Translations translations;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: Text(text)),
    );
  }
}

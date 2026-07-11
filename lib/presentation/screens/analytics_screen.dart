import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/display_name.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../widgets/amount_text.dart';
import '../widgets/app_card.dart';
import '../widgets/month_header_bar.dart';

enum _Dimension { category, tags }

/// Large enough that the user can't scroll past either edge in a session;
/// each page index maps to a calendar month offset from [_baseMonth].
const int _kInitialPage = 6000;

/// Analytics v1 (plan §3.6): month nav (arrows + swipe, like Dashboard),
/// total spent, category pie with drill-down (root → sub → subsub, "direct"
/// slice per level), and a flat tag pie via a dimension selector.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  late final DateTime _baseMonth;
  late final PageController _pageController;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  _Dimension _dimension = _Dimension.category;
  final List<Category> _breadcrumb = [];

  final Map<String, (int, List<CategorySlice>, List<TagSlice>)> _analyticsCache = {};

  @override
  void initState() {
    super.initState();
    _baseMonth = DateTime(_month.year, _month.month);
    _pageController = PageController(initialPage: _kInitialPage);
    _prefetchAdjacent();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) => DateTime(_baseMonth.year, _baseMonth.month + (page - _kInitialPage));

  String? get _currentParentId => _breadcrumb.isEmpty ? null : _breadcrumb.last.id;

  String _cacheKey(DateTime month, String? parentId) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}|${parentId ?? ''}';

  Future<(int, List<CategorySlice>, List<TagSlice>)> _fetchMonthAnalytics(DateTime month, String? parentId) async {
    final key = _cacheKey(month, parentId);
    final cached = _analyticsCache[key];
    if (cached != null) return cached;
    final analytics = ref.read(analyticsRepositoryProvider);
    final profile = await ref.read(profileRepositoryProvider).get();
    final total = await analytics.monthTotal(month, profile.currency);
    final categorySlices = await analytics.categoryBreakdown(month, parentId, profile.currency);
    final tagSlices = await analytics.tagBreakdown(month, profile.currency);
    final result = (total, categorySlices, tagSlices);
    _analyticsCache[key] = result;
    return result;
  }

  Future<void> _prefetchAdjacent() async {
    await _fetchMonthAnalytics(DateTime(_month.year, _month.month - 1), null);
    await _fetchMonthAnalytics(DateTime(_month.year, _month.month + 1), null);
  }

  void _changeMonth(int delta) {
    final target = (_pageController.page ?? _kInitialPage.toDouble()).round() + delta;
    _pageController.animateToPage(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _onPageChanged(int page) {
    setState(() {
      _month = _monthForPage(page);
      _breadcrumb.clear();
    });
    _prefetchAdjacent();
  }

  Future<void> _drillInto(String categoryId) async {
    final allCategories = await ref.read(referenceDataCacheProvider).categories();
    final node = allCategories.where((c) => c.id == categoryId);
    if (node.isEmpty) return;
    setState(() => _breadcrumb.add(node.first));
  }

  void _popBreadcrumb() => setState(() => _breadcrumb.removeLast());

  @override
  Widget build(BuildContext context) {
    ref.listen(currentTabIndexProvider, (previous, next) {
      if (next == 3 && previous != 3) {
        setState(() => _analyticsCache.clear());
        _prefetchAdjacent();
      }
    });
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;
    final profileAsync = ref.watch(profileStreamProvider);
    final currency = profileAsync.asData?.value.currency ?? 'EUR';

    return Scaffold(
      appBar: AppBar(),
      body: Column(
        children: [
          MonthHeaderBar(month: _month, onChangeMonth: _changeMonth),
          SegmentedButton<_Dimension>(
            segments: [
              ButtonSegment(
                value: _Dimension.category,
                label: Text(translations?.t('analytics.dim_category') ?? 'By Category'),
              ),
              ButtonSegment(
                value: _Dimension.tags,
                label: Text(translations?.t('analytics.dim_tag') ?? 'By Tag'),
              ),
            ],
            selected: {_dimension},
            onSelectionChanged: (s) => setState(() => _dimension = s.first),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final month = _monthForPage(index);
                final isCurrent = index == (_pageController.hasClients ? (_pageController.page?.round() ?? _kInitialPage) : _kInitialPage);
                return _MonthAnalyticsPage(
                  key: ValueKey('${_cacheKey(month, null)}-page'),
                  month: month,
                  parentId: isCurrent ? _currentParentId : null,
                  breadcrumb: isCurrent ? _breadcrumb : const [],
                  dimension: _dimension,
                  currency: currency,
                  translations: translations,
                  fetch: _fetchMonthAnalytics,
                  onDrillInto: _drillInto,
                  onPopBreadcrumb: _popBreadcrumb,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthAnalyticsPage extends ConsumerWidget {
  const _MonthAnalyticsPage({
    required super.key,
    required this.month,
    required this.parentId,
    required this.breadcrumb,
    required this.dimension,
    required this.currency,
    required this.translations,
    required this.fetch,
    required this.onDrillInto,
    required this.onPopBreadcrumb,
  });

  final DateTime month;
  final String? parentId;
  final List<Category> breadcrumb;
  final _Dimension dimension;
  final String currency;
  final Translations? translations;
  final Future<(int, List<CategorySlice>, List<TagSlice>)> Function(DateTime month, String? parentId) fetch;
  final Future<void> Function(String categoryId) onDrillInto;
  final VoidCallback onPopBreadcrumb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<(int, List<CategorySlice>, List<TagSlice>)>(
      future: fetch(month, parentId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final (total, categorySlices, tagSlices) = snapshot.data!;

        return FutureBuilder<(Map<String, String>, Map<String, bool>, Map<String, String>)>(
          future: _resolveLabels(ref, categorySlices, tagSlices),
          builder: (context, labelsSnapshot) {
            if (!labelsSnapshot.hasData) return const Center(child: CircularProgressIndicator());
            final (categoryLabels, categoryHasChildren, tagLabels) = labelsSnapshot.data!;

            final colors = context.appColors;
            final isCategory = dimension == _Dimension.category;
            final empty = isCategory ? categorySlices.isEmpty : tagSlices.isEmpty;
            final legend = isCategory
                ? _categoryLegend(categorySlices, categoryLabels, categoryHasChildren, currency)
                : _tagLegend(tagSlices, tagLabels, currency);

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                // Total + donut live inside the rounded panel; legend below it.
                AppCard.large(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    children: [
                      Text('TOTAL SPENT', style: appHeaderStyle(colors)),
                      const SizedBox(height: AppSpacing.sm),
                      AmountText(amountCents: total, currency: currency, style: appDisplay(colors, fontSize: 48)),
                      if (!empty) ...[
                        if (isCategory && breadcrumb.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          _breadcrumbRow(context),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          height: 240,
                          child: isCategory
                              ? _categoryChart(categorySlices, categoryHasChildren)
                              : _tagChart(tagSlices),
                        ),
                      ],
                    ],
                  ),
                ),
                if (empty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                      child: Text(isCategory
                          ? (translations?.t('analytics.empty_category') ?? 'No category data.')
                          : (translations?.t('analytics.empty_tag') ?? 'No tag data.')),
                    ),
                  )
                else ...[
                  const SizedBox(height: AppSpacing.lg),
                  ...legend,
                  if (!isCategory) _tagDisclaimer(context),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<(Map<String, String>, Map<String, bool>, Map<String, String>)> _resolveLabels(
    WidgetRef ref,
    List<CategorySlice> categorySlices,
    List<TagSlice> tagSlices,
  ) async {
    final loaded = this.translations ?? await ref.read(translationsProvider.future);
    final translations = loaded!;
    final allCategories = await ref.read(referenceDataCacheProvider).categories();
    final categoryById = {for (final c in allCategories) c.id: c};
    final categoryLabels = <String, String>{};
    final hasChildren = <String, bool>{};
    for (final slice in categorySlices) {
      final category = categoryById[slice.categoryId];
      if (category == null) continue;
      categoryLabels[slice.categoryId!] = displayNameFor(translations, name: category.name, isDefault: category.isDefault);
      hasChildren[slice.categoryId!] = allCategories.any((c) => c.parentId == slice.categoryId);
    }

    final allTags = await ref.read(referenceDataCacheProvider).tags();
    final tagById = {for (final t in allTags) t.id: t};
    final tagLabels = <String, String>{
      for (final slice in tagSlices)
        if (tagById[slice.tagId] != null)
          slice.tagId: displayNameFor(translations, name: tagById[slice.tagId]!.name, isDefault: tagById[slice.tagId]!.isDefault),
    };

    return (categoryLabels, hasChildren, tagLabels);
  }

  Widget _breadcrumbRow(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        // Circular back button (mock chevron button style).
        Material(
          color: colors.surfaceAlt,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPopBreadcrumb,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Icon(LucideIcons.arrowLeft300, size: 18, color: colors.text),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.smMd),
        Expanded(
          child: Text(
            breadcrumb.map((c) {
              final t = translations;
              return t == null ? c.name : displayNameFor(t, name: c.name, isDefault: c.isDefault);
            }).join('  ›  '),
            style: Theme.of(context).textTheme.labelLarge,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _categoryChart(List<CategorySlice> slices, Map<String, bool> hasChildren) {
    return PieChart(
      PieChartData(
        centerSpaceRadius: 60,
        sectionsSpace: 5,
        sections: [
          for (var i = 0; i < slices.length; i++)
            PieChartSectionData(
              value: slices[i].amountCents.abs().toDouble(),
              color: AppDataColors.cycle[i % AppDataColors.cycle.length],
              title: '',
              radius: 20,
            ),
        ],
        pieTouchData: PieTouchData(
          touchCallback: (event, response) {
            if (!event.isInterestedForInteractions) return;
            final index = response?.touchedSection?.touchedSectionIndex;
            if (index == null || index < 0) return;
            final slice = slices[index];
            if (!slice.isDirect && slice.categoryId != null && hasChildren[slice.categoryId] == true) {
              onDrillInto(slice.categoryId!);
            }
          },
        ),
      ),
    );
  }

  Widget _tagChart(List<TagSlice> slices) {
    return PieChart(
      PieChartData(
        centerSpaceRadius: 60,
        sectionsSpace: 5,
        sections: [
          for (var i = 0; i < slices.length; i++)
            PieChartSectionData(
              value: slices[i].amountCents.abs().toDouble(),
              color: AppDataColors.cycle[i % AppDataColors.cycle.length],
              title: '',
              radius: 20,
            ),
        ],
      ),
    );
  }

  List<Widget> _categoryLegend(
    List<CategorySlice> slices,
    Map<String, String> labels,
    Map<String, bool> hasChildren,
    String currency,
  ) {
    return [
      for (var i = 0; i < slices.length; i++)
        _SliceLegendRow(
          color: AppDataColors.cycle[i % AppDataColors.cycle.length],
          label: slices[i].isDirect ? 'Direct' : (labels[slices[i].categoryId] ?? ''),
          amountCents: slices[i].amountCents,
          currency: currency,
          canDrill: !slices[i].isDirect &&
              slices[i].categoryId != null &&
              hasChildren[slices[i].categoryId] == true,
          onTap: () {
            final categoryId = slices[i].categoryId;
            if (categoryId != null) onDrillInto(categoryId);
          },
        ),
    ];
  }

  List<Widget> _tagLegend(List<TagSlice> slices, Map<String, String> labels, String currency) {
    return [
      for (var i = 0; i < slices.length; i++)
        _SliceLegendRow(
          color: AppDataColors.cycle[i % AppDataColors.cycle.length],
          label: labels[slices[i].tagId] ?? '',
          amountCents: slices[i].amountCents,
          currency: currency,
        ),
    ];
  }

  Widget _tagDisclaimer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        'A transaction with several tags counts fully in each — slices can add up to more than the month total.',
        style: Theme.of(context).textTheme.bodySmall!.copyWith(fontStyle: FontStyle.italic),
      ),
    );
  }
}

class _SliceLegendRow extends StatelessWidget {
  const _SliceLegendRow({
    required this.color,
    required this.label,
    required this.amountCents,
    required this.currency,
    this.canDrill = false,
    this.onTap,
  });

  final Color color;
  final String label;
  final int amountCents;
  final String currency;
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
              '${(amountCents / 100).toStringAsFixed(2)} $currency',
              style: Theme.of(context).textTheme.labelLarge!.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
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

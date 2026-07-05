import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/display_name.dart';
import '../../core/providers/app_providers.dart';
import '../../data/database.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../widgets/entity_form_dialog.dart' show chartPalette;

enum _Dimension { category, tags }

/// Analytics v1 (plan §3.6): month nav (arrows + swipe, like Dashboard),
/// total spent, category pie with drill-down (root → sub → subsub, "direct"
/// slice per level), and a flat tag pie via a dimension selector.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  _Dimension _dimension = _Dimension.category;
  final List<Category> _breadcrumb = [];

  int _total = 0;
  List<CategorySlice> _categorySlices = [];
  List<TagSlice> _tagSlices = [];
  Map<String, String> _categoryLabels = {};
  Map<String, String> _tagLabels = {};
  Map<String, bool> _categoryHasChildren = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _currentParentId => _breadcrumb.isEmpty ? null : _breadcrumb.last.id;

  Future<void> _load() async {
    setState(() => _loading = true);
    final analytics = ref.read(analyticsRepositoryProvider);
    final translations = await ref.read(translationsProvider.future);
    final profile = await ref.read(profileRepositoryProvider).get();

    final total = await analytics.monthTotal(_month, profile.currency);
    final categorySlices = await analytics.categoryBreakdown(_month, _currentParentId, profile.currency);
    final tagSlices = await analytics.tagBreakdown(_month, profile.currency);

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

    if (!mounted) return;
    setState(() {
      _total = total;
      _categorySlices = categorySlices;
      _tagSlices = tagSlices;
      _categoryLabels = categoryLabels;
      _tagLabels = tagLabels;
      _categoryHasChildren = hasChildren;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _breadcrumb.clear();
    });
    _load();
  }

  Future<void> _drillInto(String categoryId) async {
    if (_categoryHasChildren[categoryId] != true) return; // leaf slices don't drill further
    final allCategories = await ref.read(referenceDataCacheProvider).categories();
    final node = allCategories.where((c) => c.id == categoryId);
    if (node.isEmpty) return;
    setState(() => _breadcrumb.add(node.first));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentTabIndexProvider, (previous, next) {
      if (next == 3 && previous != 3) _load();
    });
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;
    final profileAsync = ref.watch(profileStreamProvider);
    final currency = profileAsync.asData?.value.currency ?? 'EUR';

    return Scaffold(
      appBar: AppBar(title: Text(translations?.t('analytics.title') ?? 'Analytics')),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 200) _changeMonth(-1);
          if (velocity < -200) _changeMonth(1);
        },
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(icon: const Icon(LucideIcons.chevronLeft300), onPressed: () => _changeMonth(-1)),
                      Text(DateFormat.yMMMM().format(_month), style: Theme.of(context).textTheme.titleMedium),
                      IconButton(icon: const Icon(LucideIcons.chevronRight300), onPressed: () => _changeMonth(1)),
                    ],
                  ),
                  Center(
                    child: Text(
                      '${(_total / 100).toStringAsFixed(2)} $currency',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
                  if (_dimension == _Dimension.category) ..._buildCategoryView(translations, currency),
                  if (_dimension == _Dimension.tags) ..._buildTagView(translations, currency),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildCategoryView(dynamic translations, String currency) {
    if (_categorySlices.isEmpty) {
      return [Center(child: Text(translations?.t('analytics.empty_category') ?? 'No category data.'))];
    }
    return [
      if (_breadcrumb.isNotEmpty)
        Row(
          children: [
            IconButton(
              icon: const Icon(LucideIcons.arrowLeft300),
              onPressed: () {
                setState(() => _breadcrumb.removeLast());
                _load();
              },
            ),
            Expanded(
              child: Text(
                _breadcrumb
                    .map((c) => translations == null
                        ? c.name
                        : displayNameFor(translations, name: c.name, isDefault: c.isDefault))
                    .join(' > '),
              ),
            ),
          ],
        ),
      SizedBox(
        height: 240,
        child: PieChart(
          PieChartData(
            sections: [
              for (var i = 0; i < _categorySlices.length; i++)
                PieChartSectionData(
                  value: _categorySlices[i].amountCents.abs().toDouble(),
                  color: chartPalette[i % chartPalette.length],
                  title: '',
                ),
            ],
            pieTouchData: PieTouchData(
              touchCallback: (event, response) {
                if (!event.isInterestedForInteractions) return;
                final index = response?.touchedSection?.touchedSectionIndex;
                if (index == null || index < 0) return;
                final slice = _categorySlices[index];
                if (!slice.isDirect && slice.categoryId != null) _drillInto(slice.categoryId!);
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < _categorySlices.length; i++)
        _SliceLegendRow(
          color: chartPalette[i % chartPalette.length],
          label: _categorySlices[i].isDirect ? 'Direct' : (_categoryLabels[_categorySlices[i].categoryId] ?? ''),
          amountCents: _categorySlices[i].amountCents,
          currency: currency,
          canDrill: !_categorySlices[i].isDirect &&
              _categorySlices[i].categoryId != null &&
              _categoryHasChildren[_categorySlices[i].categoryId] == true,
          onTap: () {
            final categoryId = _categorySlices[i].categoryId;
            if (categoryId != null) _drillInto(categoryId);
          },
        ),
    ];
  }

  List<Widget> _buildTagView(dynamic translations, String currency) {
    if (_tagSlices.isEmpty) {
      return [Center(child: Text(translations?.t('analytics.empty_tag') ?? 'No tag data.'))];
    }
    return [
      SizedBox(
        height: 240,
        child: PieChart(
          PieChartData(
            sections: [
              for (var i = 0; i < _tagSlices.length; i++)
                PieChartSectionData(
                  value: _tagSlices[i].amountCents.abs().toDouble(),
                  color: chartPalette[i % chartPalette.length],
                  title: '',
                ),
            ],
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'A transaction with several tags counts fully in each — slices can add up to more than the month total.',
          style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
        ),
      ),
      for (var i = 0; i < _tagSlices.length; i++)
        _SliceLegendRow(
          color: chartPalette[i % chartPalette.length],
          label: _tagLabels[_tagSlices[i].tagId] ?? '',
          amountCents: _tagSlices[i].amountCents,
          currency: currency,
        ),
    ];
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
    return InkWell(
      onTap: canDrill ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(width: 12, height: 12, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text(
              '${(amountCents / 100).toStringAsFixed(2)} $currency',
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
            ),
            if (canDrill) const Icon(LucideIcons.chevronRight300, size: 16),
          ],
        ),
      ),
    );
  }
}

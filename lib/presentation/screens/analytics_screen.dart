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

  /// Whether this section is scoped to a single month (drives the header month
  /// pager). Time-series sections (window selector) and Events (event selector)
  /// are not, so they hide the month pager and show a plain title instead.
  bool get monthScoped => switch (this) {
        AnalyticsSection.trend || AnalyticsSection.cashflow || AnalyticsSection.events => false,
        _ => true,
      };

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

  IconData get icon => switch (this) {
        AnalyticsSection.category => LucideIcons.chartPie300,
        AnalyticsSection.tags => LucideIcons.tag300,
        AnalyticsSection.health => LucideIcons.heartPulse300,
        AnalyticsSection.trend => LucideIcons.trendingUp300,
        AnalyticsSection.cashflow => LucideIcons.arrowLeftRight300,
        AnalyticsSection.payment => LucideIcons.creditCard300,
        AnalyticsSection.behavior => LucideIcons.activity300,
        AnalyticsSection.quality => LucideIcons.badgeCheck300,
        AnalyticsSection.budgets => LucideIcons.target300,
        AnalyticsSection.events => LucideIcons.calendar300,
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
  /// Large enough that the user can't reach either edge in a session; each page
  /// index maps to a calendar-month offset from [_baseMonth].
  static const int _kInitialPage = 6000;

  AnalyticsSection _section = AnalyticsSection.category;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late final DateTime _baseMonth;
  late final PageController _pageController;

  /// Drill path for the Category section (empty = roots).
  final List<Category> _breadcrumb = [];

  /// Rolling window (months) for time-series sections.
  int _window = 12;

  @override
  void initState() {
    super.initState();
    _baseMonth = DateTime(_month.year, _month.month);
    _pageController = PageController(initialPage: _kInitialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) => DateTime(_baseMonth.year, _baseMonth.month + (page - _kInitialPage));

  void _changeMonth(int delta) {
    final target = (_pageController.page ?? _kInitialPage.toDouble()).round() + delta;
    _pageController.animateToPage(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _onPageChanged(int page) {
    setState(() {
      _month = _monthForPage(page);
      _breadcrumb.clear();
    });
  }

  void _selectSection(AnalyticsSection s) {
    if (s == _section) return;
    setState(() {
      _section = s;
      _breadcrumb.clear();
    });
  }

  void _openSectionMenu(Translations? translations) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _SectionMenu(
        current: _section,
        translations: translations,
        onSelect: (s) {
          Navigator.pop(ctx);
          _selectSection(s);
        },
      ),
    );
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
      floatingActionButton: _SectionFab(
        section: _section,
        onTap: () => _openSectionMenu(translations),
        onSelect: _selectSection,
      ),
      body: Column(
        children: [
          if (_section.monthScoped)
            AppTopBar(
              month: _month,
              onChangeMonth: _changeMonth,
              pageController: _pageController,
              monthForPage: _monthForPage,
              fallbackPage: _kInitialPage,
            )
          else
            AppTopBar(title: translations?.t(_section.labelKey()) ?? _section.fallbackLabel()),
          Expanded(
            // Month-scoped sections live in a swipeable [PageView] (swipe left/
            // right = prev/next month, tracked by the header label). Non-month
            // sections (window/event selectors) disable the swipe and ignore the
            // page index.
            child: PageView.builder(
              controller: _pageController,
              physics: _section.monthScoped ? null : const NeverScrollableScrollPhysics(),
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final month = _section.monthScoped ? _monthForPage(index) : _month;
                return _buildSection(month, currency, translations);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(DateTime month, String currency, Translations? translations) {
    switch (_section) {
      case AnalyticsSection.category:
        return _CategorySection(
          month: month,
          currency: currency,
          breadcrumb: _breadcrumb,
          onDrillInto: (c) => setState(() => _breadcrumb.add(c)),
          onPop: () => setState(() => _breadcrumb.removeLast()),
        );
      case AnalyticsSection.tags:
        return _TagsSection(month: month, currency: currency);
      case AnalyticsSection.health:
        return HealthSection(month: month, currency: currency);
      case AnalyticsSection.trend:
        return TrendSection(month: month, currency: currency, window: _window, onWindow: _setWindow);
      case AnalyticsSection.cashflow:
        return CashflowSection(month: month, currency: currency, window: _window, onWindow: _setWindow);
      case AnalyticsSection.payment:
        return PaymentSection(month: month, currency: currency);
      case AnalyticsSection.behavior:
        return BehaviorSection(month: month, currency: currency);
      case AnalyticsSection.quality:
        return QualitySection(month: month, currency: currency);
      case AnalyticsSection.budgets:
        return BudgetsSection(month: month, currency: currency);
      case AnalyticsSection.events:
        return EventsSection(currency: currency);
    }
  }

  void _setWindow(int w) => setState(() => _window = w);
}

/// Section-navigation FAB with two drag gestures:
/// - **vertical** steps through every section one at a time (up = next, down =
///   previous), and
/// - **horizontal left** toggles between the two **preferred** sections
///   (Categories ↔ Tags).
///
/// Tap opens the [_SectionMenu]. The vertical/horizontal recognizers are
/// distinct so a drag commits to one axis; neither collides with the body's own
/// horizontal month swipe (that lives in the [PageView], not on the FAB).
class _SectionFab extends StatefulWidget {
  const _SectionFab({
    required this.section,
    required this.onTap,
    required this.onSelect,
  });

  final AnalyticsSection section;
  final VoidCallback onTap;
  final ValueChanged<AnalyticsSection> onSelect;

  @override
  State<_SectionFab> createState() => _SectionFabState();
}

enum _DragAxis { none, vertical, horizontal }

class _SectionFabState extends State<_SectionFab> {
  /// Signed drag distance past this (in either sense) arms a switch.
  static const double _kDragStep = 24;

  /// How far the FAB is allowed to follow the finger.
  static const double _kMaxFollow = 20;

  /// The two preferred sections, in order — the horizontal-drag toggle pair.
  static final List<AnalyticsSection> _preferred =
      AnalyticsSection.values.where((s) => s.preferred).toList();

  _DragAxis _axis = _DragAxis.none;

  /// Signed distance along the active axis (dy for vertical, dx for horizontal).
  double _drag = 0;

  bool get _dragging => _axis != _DragAxis.none;

  AnalyticsSection _sectionAt(int offset) {
    const values = AnalyticsSection.values;
    final i = (widget.section.index + offset) % values.length;
    return values[i < 0 ? i + values.length : i];
  }

  /// The other preferred section (defaults to the first preferred when the
  /// current section isn't one of the pair).
  AnalyticsSection get _otherPreferred =>
      widget.section == _preferred.first ? _preferred.last : _preferred.first;

  /// The section the current drag would land on; equals the current section
  /// while below the arm threshold (so the FAB shows its own icon).
  AnalyticsSection get _target {
    if (_axis == _DragAxis.vertical) {
      if (_drag <= -_kDragStep) return _sectionAt(1); // up → next
      if (_drag >= _kDragStep) return _sectionAt(-1); // down → previous
    } else if (_axis == _DragAxis.horizontal) {
      if (_drag <= -_kDragStep) return _otherPreferred; // left → toggle preferred
    }
    return widget.section;
  }

  void _start(_DragAxis axis) => setState(() {
        _axis = axis;
        _drag = 0;
      });

  void _end() {
    final target = _target;
    if (target != widget.section) widget.onSelect(target);
    setState(() {
      _axis = _DragAxis.none;
      _drag = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final clamped = _drag.clamp(-_kMaxFollow, _kMaxFollow);
    final follow = _axis == _DragAxis.horizontal ? Offset(clamped, 0) : Offset(0, clamped);
    final armed = _target != widget.section;
    return GestureDetector(
      onVerticalDragStart: (_) => _start(_DragAxis.vertical),
      onVerticalDragUpdate: (d) => setState(() => _drag += d.delta.dy),
      onVerticalDragEnd: (_) => _end(),
      onVerticalDragCancel: _end,
      onHorizontalDragStart: (_) => _start(_DragAxis.horizontal),
      onHorizontalDragUpdate: (d) => setState(() => _drag += d.delta.dx),
      onHorizontalDragEnd: (_) => _end(),
      onHorizontalDragCancel: _end,
      child: AnimatedScale(
        scale: armed ? 1.12 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Transform.translate(
          offset: follow,
          child: FloatingActionButton(
            onPressed: widget.onTap,
            // Emphasise the button while a switch is armed so the drag reads as
            // "let go to switch".
            elevation: armed ? 12 : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 120),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
              child: Icon(
                (_dragging ? _target : widget.section).icon,
                key: ValueKey(_dragging ? _target : widget.section),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet list of every section, opened by tapping the [_SectionFab].
/// Preferred sections carry a star; the current one is highlighted.
class _SectionMenu extends StatelessWidget {
  const _SectionMenu({required this.current, required this.translations, required this.onSelect});

  final AnalyticsSection current;
  final Translations? translations;
  final ValueChanged<AnalyticsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        children: [
          for (final s in AnalyticsSection.values)
            _SectionMenuRow(
              label: translations?.t(s.labelKey()) ?? s.fallbackLabel(),
              icon: s.icon,
              selected: s == current,
              preferred: s.preferred,
              colors: colors,
              onTap: () => onSelect(s),
            ),
        ],
      ),
    );
  }
}

class _SectionMenuRow extends StatelessWidget {
  const _SectionMenuRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.preferred,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool preferred;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: colors.surfaceAlt,
      leading: Icon(
        icon,
        size: 18,
        color: preferred ? context.semanticColors.savings : colors.textMuted,
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge!.copyWith(
              color: selected ? colors.text : colors.textMuted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
      ),
      trailing: selected ? Icon(LucideIcons.check300, size: 18, color: colors.accent) : null,
      onTap: onTap,
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

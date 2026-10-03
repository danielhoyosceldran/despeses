import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format/date.dart';
import '../../core/format/money.dart';
import '../../core/haptics/haptics.dart';
import '../../core/navigation/bottom_up_route.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/analytics/analytics_math.dart';
import '../../domain/repositories/budget_repository.dart' show BudgetMonthProgress;
import '../../domain/repositories/expense_repository.dart';
import '../../domain/search/transaction_search.dart';
import '../widgets/amount_text.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/app_toast.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/drag_up_fab.dart';
import '../widgets/entity_form_dialog.dart' show chartPalette;
import '../widgets/error_retry.dart';
import '../widgets/expense_row.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/thin_progress_bar.dart';
import 'expense_entry/expense_entry_screen.dart';
import 'settings/backup_screen.dart' show RestoreNotice;

/// Month-scoped overview. Hybrid dashboard: a shared collapsing balance hero
/// (balance + Income/Spent tiles) sits above a swipeable month [PageView] whose
/// pages list the month's transactions grouped by day. The active page's inner
/// scroll drives the hero collapse.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

/// Large enough that the user can't scroll past either edge in a session;
/// each page index maps to a calendar month offset from [_baseMonth].
const int _kInitialPage = 6000;

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late final DateTime _baseMonth;
  late final PageController _pageController;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  /// Search mode: the header swaps to a search field and every month page
  /// filters its transactions by [_query] (see [TransactionQuery]).
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  TransactionQuery? _query;

  void _openSearch() {
    ref.read(hapticsProvider).selection();
    setState(() => _searching = true);
  }

  void _closeSearch() {
    _searchController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searching = false;
      _query = null;
    });
  }

  void _onQueryChanged(String text) {
    final query = TransactionQuery.parse(text);
    setState(() => _query = query.isEmpty ? null : query);
  }

  void _toggleSelection(Expense expense) {
    setState(() {
      if (_selectedIds.contains(expense.id)) {
        _selectedIds.remove(expense.id);
      } else {
        _selectedIds.add(expense.id);
      }
    });
  }

  String _monthKeyOf(DateTime month) => '${month.year}-${month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _baseMonth = DateTime(_month.year, _month.month);
    _pageController = PageController(initialPage: _kInitialPage);
    // Show the backup-restore result (R18): the screen that triggered it is
    // gone by the time the provider tree finishes rebuilding, so the message
    // is picked up here instead.
    final pendingMessage = RestoreNotice.pendingMessage;
    if (pendingMessage != null) {
      RestoreNotice.pendingMessage = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showAppToast(context, pendingMessage, variant: ToastVariant.success);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) => DateTime(_baseMonth.year, _baseMonth.month + (page - _kInitialPage));

  DateTime _monthBounds(DateTime month) => DateTime(month.year, month.month + 1, 0);

  /// Cached per month key so rebuilds (selection, month change, budgets)
  /// don't hand `StreamBuilder` a new stream instance and force a
  /// cancel/re-subscribe (loading flicker + redundant Drift query). Bounded
  /// to a handful of entries so paging through many months doesn't leak.
  final Map<String, Stream<List<Expense>>> _monthStreamCache = {};
  static const int _maxCachedMonthStreams = 12;

  Stream<List<Expense>> _watchMonth(DateTime month) {
    final key = _monthKeyOf(month);
    final cached = _monthStreamCache[key];
    if (cached != null) return cached;

    // Drift's watch streams are already multi-listener and replay the latest
    // result to each new subscriber. Don't wrap in `asBroadcastStream()`: it
    // doesn't replay, so a page rebuilt after paging away would never get data.
    final repo = ref.read(expenseRepositoryProvider);
    final stream = repo.watchAll(
      filters: ExpenseFilters(dateFrom: DateTime(month.year, month.month, 1), dateTo: _monthBounds(month)),
    );

    if (_monthStreamCache.length >= _maxCachedMonthStreams) {
      _monthStreamCache.remove(_monthStreamCache.keys.first);
    }
    _monthStreamCache[key] = stream;
    return stream;
  }

  Future<void> _onRefresh() async {
    ref.read(hapticsProvider).light();
    // Materialization is a side task: if it fails, the pull-to-refresh must
    // still reload the dashboard rather than abort with no feedback.
    try {
      await ref.read(recurringRepositoryProvider).materializeDue();
    } catch (_) {
      // Ignored on purpose; the next refresh/app start retries.
    }
  }

  void _changeMonth(int delta) {
    final target = (_pageController.page ?? _kInitialPage.toDouble()).round() + delta;
    _pageController.animateToPage(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  void _onPageChanged(int page) {
    setState(() => _month = _monthForPage(page));
  }

  /// Drops the cached stream for [month] and rebuilds so `StreamBuilder`
  /// picks up a fresh subscription instead of replaying the same error.
  void _retryMonth(DateTime month) {
    _monthStreamCache.remove(_monthKeyOf(month));
    setState(() {});
  }

  Future<void> _openEntry({String? expenseId}) async {
    await Navigator.of(context, rootNavigator: true).push<bool>(
      bottomUpRoute(ExpenseEntryScreen(expenseId: expenseId)),
    );
  }

  Future<void> _deleteSelected() async {
    final translations = ref.read(translationsProvider).asData?.value;
    final count = _selectedIds.length;
    final confirmed = await showConfirmDialog(
      context,
      title: translations?.t('dashboard.delete_title') ?? 'Delete transactions',
      message: (translations?.t('dashboard.delete_message') ?? 'Delete {{count}} selected transaction(s)?')
          .replaceAll('{{count}}', '$count'),
      destructive: true,
    );
    if (!confirmed) return;
    final repo = ref.read(expenseRepositoryProvider);
    for (final id in _selectedIds) {
      await repo.delete(id);
    }
    setState(() {
      _selectedIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final translations = translationsAsync.asData?.value;
    final profileAsync = ref.watch(profileStreamProvider);
    // The shell keeps this tab mounted (IndexedStack) while others are shown.
    // Its month stream is paused then, so writes made elsewhere don't rebuild
    // and re-lay out a hidden dashboard on every save (BL-068); the stream is
    // resumed (and re-queried) when the tab becomes visible again.
    final visible = ref.watch(currentTabIndexProvider.select((index) => index == 0));
    final currency = profileAsync.asData?.value.currency ?? 'EUR';
    final colors = context.appColors;

    final scaffold = Scaffold(
      floatingActionButton: DragUpAction(
        pageBuilder: (_, close) => ExpenseEntryScreen(onClose: close),
        builder: (context, armed, onTap) => Semantics(
          button: true,
          label: translations?.t('expenses.add') ?? 'Add expense',
          child: Tooltip(
            message: translations?.t('expenses.add') ?? 'Add expense',
            child: PressableScale(
              onTap: onTap,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.fab(colors),
                ),
                child: Icon(LucideIcons.plus300, color: colors.onAccent, size: 24),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_searching && !_selectionMode)
            _SearchBar(
              controller: _searchController,
              month: _month,
              translations: translations,
              onChanged: _onQueryChanged,
              onClose: _closeSearch,
            )
          else
            AppTopBar(
              month: _month,
              onChangeMonth: _changeMonth,
              pageController: _pageController,
              monthForPage: _monthForPage,
              fallbackPage: _kInitialPage,
              selectionCount: _selectedIds.length,
              onClearSelection: () => setState(() => _selectedIds.clear()),
              onDeleteSelection: _deleteSelected,
              actions: [
                TopBarCircleButton(
                  icon: LucideIcons.search300,
                  onTap: _openSearch,
                  semanticLabel: translations?.t('a11y.search') ?? 'Search',
                ),
                TopBarCircleButton(
                  icon: LucideIcons.refreshCw300,
                  onTap: _onRefresh,
                  semanticLabel: translations?.t('a11y.refresh') ?? 'Refresh',
                ),
              ],
            ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final month = _monthForPage(index);
                return _MonthPage(
                  key: ValueKey(_monthKeyOf(month)),
                  month: month,
                  watchExpenses: _watchMonth,
                  active: visible,
                  onRetry: _retryMonth,
                  currency: currency,
                  translations: translations,
                  onOpenEntry: _openEntry,
                  selectionMode: _selectionMode,
                  selectedIds: _selectedIds,
                  onToggleSelection: _toggleSelection,
                  query: _query,
                );
              },
            ),
          ),
        ],
      ),
    );
    // System back closes the search instead of reaching the shell's exit guard.
    // BackButtonListener needs a Router ancestor (go_router provides one).
    // Keep the listener mounted even when not searching: toggling the wrapper
    // would change the tree depth and remount the Scaffold, briefly attaching
    // two PageViews to [_pageController] (breaks the month label).
    if (Router.maybeOf(context) == null) return scaffold;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!_searching) return false;
        if (_selectionMode) {
          setState(() => _selectedIds.clear());
        } else {
          _closeSearch();
        }
        return true;
      },
      child: scaffold,
    );
  }
}

/// Header shown in search mode, in place of [AppTopBar]: close (X) · search
/// field (hint names the month being searched) · clear. Same footprint as the
/// top bar so the hero below doesn't jump.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.month,
    required this.translations,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final DateTime month;
  final Translations? translations;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final monthLabel = toBeginningOfSentenceCase(cachedDateFormat(DateFormat.YEAR_MONTH).format(month));
    final hint = (translations?.t('dashboard.search_hint') ?? 'Search {{month}}').replaceAll('{{month}}', monthLabel);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              TopBarCircleButton(
                icon: LucideIcons.x300,
                onTap: onClose,
                semanticLabel: translations?.t('a11y.close_search') ?? 'Close search',
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintMaxLines: 1,
                    isDense: true,
                    filled: true,
                    fillColor: colors.mutedFill(0.5),
                    prefixIcon: Icon(LucideIcons.search300, size: 16, color: colors.textMuted),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    suffixIcon: ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => controller.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              icon: Icon(LucideIcons.circleX300, size: 18, color: colors.textMuted),
                              tooltip: translations?.t('a11y.clear_search') ?? 'Clear search',
                              onPressed: () {
                                controller.clear();
                                onChanged('');
                              },
                            ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                      borderSide: BorderSide(color: colors.accent, width: 1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashboard mini-section (feature 3.13) surfacing recurring occurrences that
/// are due and awaiting the user's confirm/reject, as a 2-column grid capped at
/// 4 tiles. Header carries the section title (head) and a tail link that opens
/// the full Recurring screen. Tapping a tile arms it: the title/amount are
/// swapped for a reject (✕) / accept (✓) pair for 3s, then it auto-reverts.
/// Arming a different tile reverts the previous one. Accepting confirms the
/// occurrence into a real transaction; the stream then drops it and the next
/// pending item (5th onward) takes its place.
class _RecurringDueSection extends ConsumerStatefulWidget {
  const _RecurringDueSection({required this.translations});

  final Translations? translations;

  @override
  ConsumerState<_RecurringDueSection> createState() => _RecurringDueSectionState();
}

class _RecurringDueSectionState extends ConsumerState<_RecurringDueSection> {
  /// Occurrence id currently showing its accept/reject controls, or null.
  String? _armedId;
  Timer? _revertTimer;
  // Occurrences whose accept/reject is in flight, so a double tap is ignored.
  final Set<String> _busyIds = {};

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  void _arm(String id) {
    ref.read(hapticsProvider).selection();
    _revertTimer?.cancel();
    // Tapping the armed tile again folds it back.
    if (_armedId == id) {
      setState(() => _armedId = null);
      return;
    }
    setState(() => _armedId = id);
    _revertTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _armedId = null);
    });
  }

  Future<void> _accept(RecurringOccurrence occ) async {
    if (!_busyIds.add(occ.id)) return;
    _revertTimer?.cancel();
    ref.read(hapticsProvider).medium();
    _armedId = null; // stream will rebuild without this tile
    try {
      await ref.read(recurringRepositoryProvider).confirm(occ);
    } finally {
      _busyIds.remove(occ.id);
    }
  }

  Future<void> _reject(RecurringOccurrence occ) async {
    if (!_busyIds.add(occ.id)) return;
    _revertTimer?.cancel();
    ref.read(hapticsProvider).light();
    _armedId = null;
    try {
      await ref.read(recurringRepositoryProvider).skip(occ.id);
    } finally {
      _busyIds.remove(occ.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingRecurringProvider).asData?.value ?? const <RecurringOccurrence>[];
    if (pending.isEmpty) return const SizedBox.shrink();
    final colors = context.appColors;
    final t = widget.translations;
    final visible = pending.take(4).toList();
    // Drop a stale armed id once its tile is gone (accepted/rejected).
    if (_armedId != null && !visible.any((o) => o.id == _armedId)) {
      _armedId = null;
    }

    // Rendered inside the month page's already-padded content list, directly
    // below the active-budgets block, so no outer horizontal padding here.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.smMd),
          child: Row(
              children: [
                Expanded(
                  child: Text(
                    (t?.t('dashboard.recurring_due') ?? 'Recurring due').toUpperCase(),
                    style: appHeaderStyle(colors),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(AppDimens.radiusCard),
                  onTap: () => context.push('/settings/recurring'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t?.t('recurring.review') ?? 'Review',
                          style: TextStyle(color: colors.accent, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                        const SizedBox(width: 2),
                        Icon(LucideIcons.chevronRight300, size: 14, color: colors.accent),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        _RecurringDueGrid(
          occurrences: visible,
          armedId: _armedId,
          onArm: _arm,
          onAccept: _accept,
          onReject: _reject,
        ),
      ],
    );
  }
}

/// 2-column grid mirroring the budget grid rules: 1 row for ≤2 items, 2 rows
/// for 3–4, with a placeholder filling any trailing gap to keep alignment.
class _RecurringDueGrid extends StatelessWidget {
  const _RecurringDueGrid({
    required this.occurrences,
    required this.armedId,
    required this.onArm,
    required this.onAccept,
    required this.onReject,
  });

  final List<RecurringOccurrence> occurrences;
  final String? armedId;
  final void Function(String id) onArm;
  final void Function(RecurringOccurrence occ) onAccept;
  final void Function(RecurringOccurrence occ) onReject;

  @override
  Widget build(BuildContext context) {
    final rows = occurrences.length <= 2 ? 1 : 2;
    final cells = <RecurringOccurrence?>[...occurrences];
    while (cells.length < rows * 2) {
      cells.add(null);
    }

    Widget cell(RecurringOccurrence? occ) => Expanded(
          child: occ == null
              ? const _RecurringDuePlaceholder()
              : _RecurringDueTile(
                  occ: occ,
                  armed: occ.id == armedId,
                  onArm: () => onArm(occ.id),
                  onAccept: () => onAccept(occ),
                  onReject: () => onReject(occ),
                ),
        );

    return Column(
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cell(cells[r * 2]),
                const SizedBox(width: AppSpacing.sm),
                cell(cells[r * 2 + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Empty trailing slot keeping the grid aligned (mirrors `_BudgetPlaceholder`).
class _RecurringDuePlaceholder extends StatelessWidget {
  const _RecurringDuePlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        color: colors.surfaceAlt.withValues(alpha: 0.4),
      ),
    );
  }
}

/// A single due-occurrence tile. Default face: one row with the name on the
/// left and the signed amount on the right. Armed face: a split reject (✕) /
/// accept (✓) control. Cross-fades between the two.
class _RecurringDueTile extends StatelessWidget {
  const _RecurringDueTile({
    required this.occ,
    required this.armed,
    required this.onArm,
    required this.onAccept,
    required this.onReject,
  });

  final RecurringOccurrence occ;
  final bool armed;
  final VoidCallback onArm;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          border: Border.all(color: colors.borderSoft, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: armed ? _buildArmed(context) : _buildFace(context),
        ),
      ),
    );
  }

  Widget _buildFace(BuildContext context) {
    final colors = context.appColors;
    final sign = switch (occ.type) {
      'income' => '+',
      'refund' => '±',
      _ => '-',
    };
    final amountColor = context.amountColorForType(occ.type);
    final title = occ.description?.isNotEmpty == true ? occ.description! : occ.type;
    return InkWell(
      key: const ValueKey('face'),
      onTap: onArm,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.smMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$sign${formatMoney(occ.amount, occ.currency)}',
              style: appDisplay(colors, fontSize: 16, color: amountColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArmed(BuildContext context) {
    final colors = context.appColors;
    final semantic = context.semanticColors;
    Widget action({
      required IconData icon,
      required Color color,
      required VoidCallback onTap,
    }) =>
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Container(
              color: pillBackground(color),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 22),
            ),
          ),
        );
    return Row(
      key: const ValueKey('armed'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        action(icon: LucideIcons.x300, color: semantic.expense, onTap: onReject),
        Container(width: 1, color: colors.borderSoft),
        action(icon: LucideIcons.check300, color: semantic.income, onTap: onAccept),
      ],
    );
  }
}

/// Monthly totals in the profile currency, per the shared definition in
/// analytics_math.dart: spent = expense − refund; savings (ahorro) are shown
/// apart, not as spending, but still reduce the balance.
class _Totals {
  const _Totals({required this.spent, required this.savings, required this.income});
  final int spent;
  final int savings;
  final int income;
  int get balance => income - spent - savings;

  factory _Totals.of(List<Expense> expenses, String currency) {
    // Scheduled (future-dated) rows are listed but don't count until their day.
    final inCurrency = expenses.where((e) => e.currency == currency && !isScheduled(e)).toList();
    return _Totals(
      spent: expenseOutflow(inCurrency),
      savings: savingsSetAside(inCurrency),
      income: sumOfType(inCurrency, 'income'),
    );
  }
}

/// Collapsing balance hero. [t] 0→1: balance shrinks 60→30, the Income/Spent
/// tiles fold away, and a hairline bottom border fades in.
///
/// Rebuilt on every scroll frame, so it only composes cheap per-frame wrappers
/// (scale, fold, fade, padding) around children built once per data change by
/// [_HeroHeaderDelegate] (BL-058): the texts are laid out once at their full
/// size and then scaled at paint time, never re-measured per frame.
class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.t, required this.label, required this.amount, required this.tiles});

  final double t;
  final Widget label;
  final Widget amount;
  final Widget tiles;

  /// The tiles finish fading in the first half of the collapse; from there on
  /// opacity is 0 (nothing painted) and the fold alone hides them, so the
  /// offscreen layer an intermediate opacity needs only exists half the time.
  static const _fade = Interval(0, 0.5);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ClipRect(
      child: Container(
      width: double.infinity,
      alignment: Alignment.topCenter,
      color: colors.bg,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        lerpDouble(AppSpacing.md, AppSpacing.sm, t)!,
        AppSpacing.lg,
        lerpDouble(0, AppSpacing.smMd, t)!,
      ),
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider.withValues(alpha: t), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ScaledFromTop(scale: lerpDouble(1, _HeroHeaderDelegate.labelMinSize / _HeroHeaderDelegate.labelMaxSize, t)!, child: label),
          const SizedBox(height: AppSpacing.xs),
          _ScaledFromTop(scale: lerpDouble(1, _HeroHeaderDelegate.amountMinSize / _HeroHeaderDelegate.amountMaxSize, t)!, child: amount),
          // Income / Spent tiles collapse away as t → 1.
          ClipRect(
            child: Align(
              heightFactor: (1 - t).clamp(0.0, 1.0),
              child: Opacity(
                opacity: 1 - _fade.transform(t),
                child: tiles,
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Paints [child] scaled by [scale] from its top-center and occupies only the
/// scaled height. The child is laid out once at full size (same constraints
/// every frame, so layout is skipped); only the paint transform changes.
class _ScaledFromTop extends StatelessWidget {
  const _ScaledFromTop({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: scale,
      child: Transform.scale(scale: scale, alignment: Alignment.topCenter, child: child),
    );
  }
}

/// The three Income/Spent/Savings tiles, as one row.
class _StatTilesRow extends StatelessWidget {
  const _StatTilesRow({required this.totals, required this.currency, required this.translations});

  final _Totals totals;
  final String currency;
  final Translations? translations;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              label: translations?.t('analytics.income') ?? 'Income',
              value: totals.income,
              currency: currency,
              icon: LucideIcons.arrowDownRight,
              color: semantic.income,
            ),
          ),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: _StatTile(
              label: translations?.t('analytics.spent') ?? 'Spent',
              value: totals.spent,
              currency: currency,
              icon: LucideIcons.arrowUpRight,
              color: semantic.expense,
            ),
          ),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: _StatTile(
              label: translations?.t('expenses.type_ahorro') ?? 'Savings',
              value: totals.savings,
              currency: currency,
              icon: LucideIcons.coins300,
              color: semantic.savings,
            ),
          ),
        ],
      ),
    );
  }
}

/// Income/Spent/Savings stat tile (three in a row): muted fill, hairline
/// border; a small colored icon chip beside the label, the amount below it,
/// scaled down to fit the narrow tile.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.currency,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final String currency;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smMd),
      decoration: BoxDecoration(
        color: colors.mutedFill(0.30),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        border: Border.all(color: colors.borderSoft, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: iconChipBackground(color), shape: BoxShape.circle),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AmountText(
              amountCents: value,
              currency: currency,
              style: appDisplay(colors, fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthPage extends ConsumerWidget {
  const _MonthPage({
    required super.key,
    required this.month,
    required this.watchExpenses,
    required this.active,
    required this.onRetry,
    required this.currency,
    required this.translations,
    required this.onOpenEntry,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelection,
    this.query,
  });

  final DateTime month;
  final Stream<List<Expense>> Function(DateTime month) watchExpenses;

  /// False while the dashboard tab is hidden: the stream is detached and the
  /// last snapshot keeps being shown (StreamBuilder retains its data).
  final bool active;
  final void Function(DateTime month) onRetry;
  final String currency;
  final Translations? translations;
  final Future<void> Function({String? expenseId}) onOpenEntry;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Expense expense) onToggleSelection;

  /// Active search; when set, only matching transactions are listed and the
  /// budgets / recurring-due sections are hidden. Hero totals stay monthly.
  final TransactionQuery? query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<Expense>>(
      stream: active ? watchExpenses(month) : null,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorRetry(
            onRetry: () => onRetry(month),
            message: translations?.t('dashboard.error_load_month') ?? 'Could not load this month.',
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final monthExpenses = snapshot.data!;
        final searching = query != null;
        final derived = _MonthDerived.of(monthExpenses, query, currency, translations);
        final expenses = derived.expenses;
        final colors = context.appColors;

        // Fixed sections above the transaction list (a handful of widgets).
        final header = <Widget>[
          if (searching)
            _SearchSummary(expenses: expenses, currency: currency, translations: translations)
          else
            _ActiveBudgets(month: month, active: active, translations: translations),
          if (!selectionMode && !searching) ...[
            _RecurringDueSection(translations: translations),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (expenses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text(
                  searching
                      ? translations?.t('dashboard.search_no_results') ?? 'No matching transactions'
                      : translations?.t('dashboard.no_transactions') ?? 'No transactions',
                ),
              ),
            ),
        ];

        // The transaction list is built lazily (BL-057): only the day headers
        // and rows on screen are created, instead of every row of the month.
        final items = derived.items;
        Widget buildItem(BuildContext context, int index) {
          final item = items[index];
          if (item is Expense) {
            return ExpenseRow(
              key: ValueKey(item.id),
              expense: item,
              translations: translations,
              selectionMode: selectionMode,
              selected: selectedIds.contains(item.id),
              onTap: () => selectionMode ? onToggleSelection(item) : onOpenEntry(expenseId: item.id),
              onLongPress: () => onToggleSelection(item),
            );
          }
          if (item is _DayGroup) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.xs, AppSpacing.smMd),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(item.label, style: appHeaderStyle(colors)),
                  Text(
                    _signed(item.total, currency),
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: item.total >= 0 ? context.semanticColors.income : colors.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ],
              ),
            );
          }
          // _groupGap: spacing after a day's last row.
          return const SizedBox(height: AppSpacing.smMd);
        }

        return CustomScrollView(
          // Always scrollable so the hero can collapse even on short months.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Scroll-driven collapsing hero: shrinkOffset (0 → maxExtent-minExtent)
            // is the animation clock — the scroll position IS the value.
            SliverPersistentHeader(
              pinned: true,
              delegate: _HeroHeaderDelegate(totals: derived.totals, currency: currency, translations: translations),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.fabClearance),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverList.list(children: header),
                  SliverList.builder(itemCount: items.length, itemBuilder: buildItem),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Marker item: vertical gap after the last row of a day group.
const _groupGap = Object();

/// Everything [_MonthPage] derives from one stream snapshot: the (searched)
/// transactions, the flattened lazy-list items (day headers, rows, gaps) and
/// the hero totals. Memoized per snapshot list (BL-057), so rebuilds that
/// don't change the data — selection, budgets reload, tab switches — don't
/// re-filter, re-group and re-total the whole month.
class _MonthDerived {
  _MonthDerived._(this.query, this.currency, this.translations, this.today, this.expenses, this.items, this.totals);

  final TransactionQuery? query;
  final String currency;
  final Translations? translations;

  /// Day the "Today"/"Yesterday" labels were computed for.
  final DateTime today;
  final List<Expense> expenses;

  /// [_DayGroup] header, then its [Expense] rows, then [_groupGap]; per day.
  final List<Object> items;
  final _Totals totals;

  static final _cache = Expando<_MonthDerived>('monthDerived');

  static _MonthDerived of(
    List<Expense> monthExpenses,
    TransactionQuery? query,
    String currency,
    Translations? translations,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cached = _cache[monthExpenses];
    if (cached != null &&
        identical(cached.query, query) &&
        cached.currency == currency &&
        identical(cached.translations, translations) &&
        cached.today == today) {
      return cached;
    }
    final expenses = query != null ? monthExpenses.where(query.matches).toList() : monthExpenses;
    final items = <Object>[];
    for (final group in _groupByDay(expenses, currency, translations)) {
      items
        ..add(group)
        ..addAll(group.items)
        ..add(_groupGap);
    }
    final derived = _MonthDerived._(
        query, currency, translations, today, expenses, items, _Totals.of(monthExpenses, currency));
    _cache[monthExpenses] = derived;
    return derived;
  }
}

/// Search results header: uppercase result count (left) + the signed net of
/// the matches in the profile currency (right), styled like a day header.
class _SearchSummary extends StatelessWidget {
  const _SearchSummary({required this.expenses, required this.currency, required this.translations});

  final List<Expense> expenses;
  final String currency;
  final Translations? translations;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final net = expenses.where((e) => e.currency == currency).fold<int>(0, (sum, e) => sum + _signedCents(e));
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.smMd),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            (translations?.t('dashboard.search_results') ?? '{{count}} results')
                .replaceAll('{{count}}', '${expenses.length}')
                .toUpperCase(),
            style: appHeaderStyle(colors),
          ),
          if (expenses.isNotEmpty)
            Text(
              _signed(net, currency),
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: net >= 0 ? context.semanticColors.income : colors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
        ],
      ),
    );
  }
}

/// Pinned collapsing hero. [shrinkOffset] maps linearly to t (0 = expanded,
/// 1 = collapsed): the scroll drives the balance shrink and the Income/Spent
/// tiles folding away, simultaneously, 1:1 with the finger.
///
/// [build] runs on every scroll frame. The label, amount and tiles are built
/// once per delegate (i.e. per data change) and handed to [_BalanceHeader] as
/// the *same* widget instances each frame, so Flutter skips rebuilding them:
/// no money formatting and no text layout while scrolling (BL-058).
class _HeroHeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeroHeaderDelegate({required this.totals, required this.currency, required this.translations});

  final _Totals totals;
  final String currency;
  final Translations? translations;

  static const double _min = 88;
  static const double _max = 244;

  /// Font sizes at t = 0 / t = 1. Texts are laid out at the max size and
  /// scaled down at paint time.
  static const double labelMaxSize = 13;
  static const double labelMinSize = 12;
  static const double amountMaxSize = 60;
  static const double amountMinSize = 30;

  ThemeData? _builtForTheme;
  late Widget _label;
  late Widget _amount;
  late Widget _tiles;

  void _ensureChildren(BuildContext context) {
    final theme = Theme.of(context);
    if (identical(theme, _builtForTheme)) return;
    _builtForTheme = theme;
    final colors = context.appColors;
    _label = Text(
      translations?.t('dashboard.total_balance') ?? 'Total Balance',
      style: theme.textTheme.labelSmall!.copyWith(fontSize: labelMaxSize),
    );
    _amount = AmountText(
      amountCents: totals.balance,
      currency: currency,
      style: appDisplay(colors, fontSize: amountMaxSize),
    );
    _tiles = RepaintBoundary(
      child: _StatTilesRow(totals: totals, currency: currency, translations: translations),
    );
  }

  @override
  double get minExtent => _min;
  @override
  double get maxExtent => _max;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    _ensureChildren(context);
    final t = (shrinkOffset / (_max - _min)).clamp(0.0, 1.0);
    return RepaintBoundary(
      child: _BalanceHeader(t: t, label: _label, amount: _amount, tiles: _tiles),
    );
  }

  @override
  bool shouldRebuild(_HeroHeaderDelegate old) =>
      old.totals.spent != totals.spent ||
      old.totals.savings != totals.savings ||
      old.totals.income != totals.income ||
      old.currency != currency ||
      old.translations != translations;
}

/// A day bucket of transactions in display order, with its signed total.
class _DayGroup {
  _DayGroup(this.label);
  final String label;
  final List<Expense> items = [];
  int total = 0;
}

int _signedCents(Expense e) => switch (e.type) {
      'income' => e.amount,
      'refund' => e.amount,
      _ => -e.amount,
    };

String _signed(int cents, String currency) {
  final sign = cents > 0 ? '+' : '';
  return '$sign${formatMoney(cents, currency)}';
}

String _dayLabel(DateTime date, Translations? translations) {
  final now = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return (translations?.t('dashboard.today') ?? 'Today').toUpperCase();
  if (diff == 1) return (translations?.t('dashboard.yesterday') ?? 'Yesterday').toUpperCase();
  return cachedDateFormat(DateFormat.ABBR_MONTH_WEEKDAY_DAY).format(date).toUpperCase();
}

List<_DayGroup> _groupByDay(List<Expense> expenses, String currency, Translations? translations) {
  final groups = <_DayGroup>[];
  final index = <String, int>{};
  for (final e in expenses) {
    final key = '${e.date.year}-${e.date.month}-${e.date.day}';
    var i = index[key];
    if (i == null) {
      i = groups.length;
      index[key] = i;
      groups.add(_DayGroup(_dayLabel(e.date, translations)));
    }
    groups[i].items.add(e);
    if (e.currency == currency) groups[i].total += _signedCents(e);
  }
  return groups;
}

/// The month's active budgets (title + [_BudgetGrid]), or nothing when there
/// are none. Live via [budgetProgressProvider] (BL-063): saving or deleting a
/// transaction anywhere updates it without manual reloads. While the dashboard
/// tab is hidden ([active] false) it stops listening and keeps showing the
/// last value, so writes on other tabs don't rebuild it (BL-068); the
/// provider's cache makes resuming instant.
class _ActiveBudgets extends ConsumerStatefulWidget {
  const _ActiveBudgets({required this.month, required this.active, required this.translations});

  final DateTime month;
  final bool active;
  final Translations? translations;

  @override
  ConsumerState<_ActiveBudgets> createState() => _ActiveBudgetsState();
}

class _ActiveBudgetsState extends ConsumerState<_ActiveBudgets> {
  BudgetMonthProgress? _last;

  @override
  Widget build(BuildContext context) {
    final month = DateTime(widget.month.year, widget.month.month);
    if (widget.active) {
      _last = ref.watch(budgetProgressProvider(month)).valueOrNull ?? _last;
    }
    final progress = _last;
    if (progress == null) return const SizedBox.shrink();
    final budgetRepo = ref.read(budgetRepositoryProvider);
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final active = progress.budgets.where((b) => budgetRepo.isActiveForMonth(b, monthKey)).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.smMd),
          child: Text(
            (widget.translations?.t('dashboard.active_budgets') ?? 'Active budgets').toUpperCase(),
            style: appHeaderStyle(context.appColors),
          ),
        ),
        _BudgetGrid(budgets: active.take(4).toList(), progress: progress.spent),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// The dashboard's active-budgets preview: a fixed 2-column grid, capped at 4
/// budgets. 1–2 budgets fill a single row; 3–4 fill a 2×2 grid, padding the
/// trailing gap with an empty slot so cells stay aligned. Every cell taps
/// through to the Budgets tab.
class _BudgetGrid extends StatelessWidget {
  const _BudgetGrid({required this.budgets, required this.progress});

  final List<Budget> budgets;
  final Map<String, int> progress;

  @override
  Widget build(BuildContext context) {
    final rows = budgets.length <= 2 ? 1 : 2;
    final cells = <Widget?>[
      for (final b in budgets) _BudgetProgressTile(budget: b, spent: progress[b.id] ?? 0),
    ];
    while (cells.length < rows * 2) {
      cells.add(null);
    }

    Widget cell(Widget? w) => Expanded(child: w ?? const _BudgetPlaceholder());

    return Column(
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cell(cells[r * 2]),
                const SizedBox(width: AppSpacing.sm),
                cell(cells[r * 2 + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Empty slot filling a trailing gap in the budget grid: a plain rounded grey
/// patch (theme-aware, no content) that reads as "something missing here" while
/// keeping the row aligned. Stretched to a tile's height by the row.
class _BudgetPlaceholder extends StatelessWidget {
  const _BudgetPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        color: colors.surfaceAlt.withValues(alpha: 0.4),
      ),
    );
  }
}

class _BudgetProgressTile extends ConsumerWidget {
  const _BudgetProgressTile({required this.budget, required this.spent});

  final Budget budget;
  final int spent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratio = budget.amount == 0 ? 0.0 : (spent / budget.amount).clamp(0.0, 1.0);
    final over = spent > budget.amount;
    final semantic = context.semanticColors;
    final colors = context.appColors;
    final theme = Theme.of(context);
    final categoryColor = chartPalette[(budget.categoryId ?? budget.id).hashCode % chartPalette.length];
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      child: InkWell(
        onTap: () => context.go('/budgets'),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
            border: Border.all(color: colors.borderSoft, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      budget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${budget.amount == 0 ? 0 : (spent / budget.amount * 100).round()}%',
                    style: theme.textTheme.bodySmall!.copyWith(
                          color: over ? semantic.over : colors.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ThinProgressBar(value: ratio, fillColor: over ? semantic.over : categoryColor),
            ],
          ),
        ),
      ),
    );
  }
}

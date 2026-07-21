import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/feature_flags.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// Bottom nav with 5 tabs: Dashboard · Expenses · Budgets · Analytics ·
/// Settings. The web app only routes 4 (Expenses is dead code there); here it
/// gets its own tab (plan §6, §3.4). Export lives inside Settings.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  /// Window in which a second back press confirms exit ("press back again").
  static const _exitWindow = Duration(seconds: 2);
  DateTime? _lastBackAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _materializeDue();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The shell (and its tabs, kept in an internal IndexedStack) is built
    // once for the app's lifetime, so a launch-time-only materialize misses
    // recurrences that become due while the app stays open/backgrounded —
    // re-check on resume as well as on returning to the Dashboard tab (feature
    // 3.13).
    if (state == AppLifecycleState.resumed) _materializeDue();
  }

  /// Fire-and-forget: failures are non-fatal, the pending inbox just won't
  /// gain new entries this pass. `watchPending`/`watchPendingCount` streams
  /// pick up any newly-materialized occurrences automatically.
  void _materializeDue() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[AppShell] materializeDue triggered');
      ref.read(recurringRepositoryProvider).materializeDue();
    });
  }

  static const _labels = [
    'Dashboard',
    'Expenses',
    'Budgets',
    'Analytics',
    'Manage',
  ];
  static const _icons = [
    LucideIcons.layoutDashboard300,
    LucideIcons.receipt300,
    LucideIcons.pieChart300,
    LucideIcons.barChart2300,
    LucideIcons.layers300,
  ];
  static const _keys = [
    'nav.dashboard',
    'nav.expenses',
    'nav.budgets',
    'nav.analytics',
    'nav.settings',
  ];

  static final _visibleIndices = [
    0,
    if (FeatureFlags.showExpensesScreen) 1,
    2,
    3,
    4,
  ];

  @override
  Widget build(BuildContext context) {
    final translationsAsync = ref.watch(translationsProvider);
    final t = translationsAsync.asData?.value;


    final navigationShell = widget.navigationShell;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(currentTabIndexProvider.notifier);
      if (notifier.state != navigationShell.currentIndex) {
        notifier.state = navigationShell.currentIndex;
      }
    });

    return PopScope(
      // The shell is the root route: when there is nothing left to pop, a
      // system back press would close the app. Require a second back press
      // within a short window before actually exiting ("press back again").
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackAt != null && now.difference(_lastBackAt!) < _exitWindow) {
          SystemNavigator.pop();
          return;
        }
        _lastBackAt = now;
        showAppToast(context, t?.t('exit.toast') ?? 'Press back again to exit');
      },
      child: Scaffold(
      // NOTE: do NOT wrap [navigationShell] in an AnimatedSwitcher/any widget
      // that keeps two copies mounted at once. StatefulNavigationShell carries
      // a single internal GlobalKey, so cross-fading tab changes mounts that
      // key twice for a frame → "Duplicate GlobalKey detected" crash. The
      // shell's own IndexedStack already switches branches instantly. A real
      // tab transition would need StatefulShellRoute.navigatorContainerBuilder.
      body: navigationShell,
      bottomNavigationBar: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < 200) return;
          final delta = velocity < 0 ? 1 : -1;
          final currentPos = _visibleIndices.indexOf(navigationShell.currentIndex);
          final targetPos = currentPos + delta;
          if (targetPos < 0 || targetPos >= _visibleIndices.length) return;
          final targetIndex = _visibleIndices[targetPos];
          if (targetIndex == 0) _materializeDue();
          navigationShell.goBranch(targetIndex);
        },
        child: _NavBar(
          activePos: _visibleIndices.indexOf(navigationShell.currentIndex),
          icons: [for (final i in _visibleIndices) _icons[i]],
          labels: [for (final i in _visibleIndices) t?.t(_keys[i]) ?? _labels[i]],
          onSelect: (pos) {
            final index = _visibleIndices[pos];
            if (index == 0) _materializeDue();
            navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
          },
        ),
      ),
      ),
    );
  }
}

/// Custom bottom nav with a morphing "pill" that slides behind the active
/// icon. Matches the mock: `bg-card`, top border, 10px labels, active tint.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.activePos,
    required this.icons,
    required this.labels,
    required this.onSelect,
  });

  final int activePos;
  final List<IconData> icons;
  final List<String> labels;
  final ValueChanged<int> onSelect;

  static const double _contentHeight = 60;
  static const double _pillWidth = 56;
  static const double _pillHeight = 34;
  static const double _pillTop = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final n = icons.length;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border, width: 1)),
      ),
      padding: EdgeInsets.only(bottom: bottomSafe),
      child: SizedBox(
        height: _contentHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tabW = constraints.maxWidth / n;
            final pillLeft = activePos * tabW + (tabW - _pillWidth) / 2;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  left: pillLeft,
                  top: _pillTop,
                  width: _pillWidth,
                  height: _pillHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.mutedFill(0.8),
                      borderRadius: BorderRadius.circular(AppDimens.radiusButton),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var pos = 0; pos < n; pos++)
                      SizedBox(
                        width: tabW,
                        child: _NavTab(
                          icon: icons[pos],
                          label: labels[pos],
                          active: pos == activePos,
                          onTap: () => onSelect(pos),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = active ? colors.accent : colors.textMuted;
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }
}

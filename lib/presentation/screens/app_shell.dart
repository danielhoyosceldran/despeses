import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/feature_flags.dart';
import '../../core/providers/app_providers.dart';

/// Bottom nav with 5 tabs: Dashboard · Expenses · Budgets · Analytics ·
/// Settings. The web app only routes 4 (Expenses is dead code there); here it
/// gets its own tab (plan §6, §3.4). Export lives inside Settings.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Window in which a second back press confirms exit ("press back again").
  static const _exitWindow = Duration(seconds: 2);
  DateTime? _lastBackAt;

  static const _labels = [
    'Dashboard',
    'Expenses',
    'Budgets',
    'Analytics',
    'Settings',
  ];
  static const _icons = [
    LucideIcons.layoutDashboard300,
    LucideIcons.receipt300,
    LucideIcons.pieChart300,
    LucideIcons.barChart2300,
    LucideIcons.settings300,
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
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              t?.t('exit.toast') ?? 'Press back again to exit',
            ),
            duration: _exitWindow,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(animation);
          return ClipRect(
            child: SlideTransition(
              position: slide,
              child: FadeTransition(opacity: animation, child: child),
            ),
          );
        },
        layoutBuilder: (currentChild, previousChildren) => Stack(
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        child: KeyedSubtree(
          key: ValueKey(navigationShell.currentIndex),
          child: navigationShell,
        ),
      ),
      bottomNavigationBar: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < 200) return;
          final delta = velocity < 0 ? 1 : -1;
          final currentPos = _visibleIndices.indexOf(navigationShell.currentIndex);
          final targetPos = currentPos + delta;
          if (targetPos < 0 || targetPos >= _visibleIndices.length) return;
          navigationShell.goBranch(_visibleIndices[targetPos]);
        },
        child: NavigationBar(
          selectedIndex: _visibleIndices.indexOf(navigationShell.currentIndex),
          onDestinationSelected: (pos) {
            final index = _visibleIndices[pos];
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          },
          destinations: [
            for (final i in _visibleIndices)
              NavigationDestination(
                icon: Icon(_icons[i]),
                label: t?.t(_keys[i]) ?? _labels[i],
              ),
          ],
        ),
      ),
      ),
    );
  }
}

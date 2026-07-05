import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';

/// Bottom nav with 5 tabs: Dashboard · Expenses · Budgets · Analytics ·
/// Settings. The web app only routes 4 (Expenses is dead code there); here it
/// gets its own tab (plan §6, §3.4). Export lives inside Settings.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _labels = ['Dashboard', 'Expenses', 'Budgets', 'Analytics', 'Settings'];
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translationsAsync = ref.watch(translationsProvider);
    final t = translationsAsync.asData?.value;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          for (var i = 0; i < _labels.length; i++)
            NavigationDestination(
              icon: Icon(_icons[i]),
              label: t?.t(_keys[i]) ?? _labels[i],
            ),
        ],
      ),
    );
  }
}

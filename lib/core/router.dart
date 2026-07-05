import 'package:go_router/go_router.dart';

import 'config/feature_flags.dart';
import '../presentation/screens/analytics_screen.dart';
import '../presentation/screens/app_shell.dart';
import '../presentation/screens/budgets_screen.dart';
import '../presentation/screens/dashboard_screen.dart';
import '../presentation/screens/expenses_screen.dart';
import '../presentation/screens/settings/backup_screen.dart';
import '../presentation/screens/settings/categories_screen.dart';
import '../presentation/screens/settings/export_screen.dart';
import '../presentation/screens/settings/events_screen.dart';
import '../presentation/screens/settings/payment_methods_screen.dart';
import '../presentation/screens/settings/profile_screen.dart';
import '../presentation/screens/settings/projects_screen.dart';
import '../presentation/screens/settings/tag_groups_screen.dart';
import '../presentation/screens/settings/tags_screen.dart';
import '../presentation/screens/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) => const DashboardScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/expenses',
              redirect: (context, state) =>
                  FeatureFlags.showExpensesScreen ? null : '/dashboard',
              builder: (context, state) => const ExpensesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/budgets',
              builder: (context, state) => const BudgetsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/analytics',
              builder: (context, state) => const AnalyticsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'categories',
                  builder: (context, state) => const CategoriesScreen(),
                ),
                GoRoute(
                  path: 'tags',
                  builder: (context, state) => const TagsScreen(),
                ),
                GoRoute(
                  path: 'tag-groups',
                  builder: (context, state) => const TagGroupsScreen(),
                ),
                GoRoute(
                  path: 'payment-methods',
                  builder: (context, state) => const PaymentMethodsScreen(),
                ),
                GoRoute(
                  path: 'events',
                  builder: (context, state) => const EventsScreen(),
                ),
                GoRoute(
                  path: 'projects',
                  builder: (context, state) => const ProjectsScreen(),
                ),
                GoRoute(
                  path: 'profile',
                  builder: (context, state) => const ProfileScreen(),
                ),
                GoRoute(
                  path: 'backup',
                  builder: (context, state) => const BackupScreen(),
                ),
                GoRoute(
                  path: 'export',
                  builder: (context, state) => const ExportScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

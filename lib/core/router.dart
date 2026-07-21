import 'package:go_router/go_router.dart';

import 'config/feature_flags.dart';
import 'navigation/slide_from_right_route.dart';
import 'navigation/top_down_route.dart';
import '../presentation/screens/account_screen.dart';
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
import '../presentation/screens/recurring/recurring_screen.dart';
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
                  pageBuilder: (context, state) => slideFromRightPage(
                    state: state,
                    child: const CategoriesScreen(),
                  ),
                ),
                GoRoute(
                  path: 'tags',
                  pageBuilder: (context, state) => slideFromRightPage(
                    state: state,
                    child: const TagsScreen(),
                  ),
                ),
                GoRoute(
                  path: 'tag-groups',
                  pageBuilder: (context, state) => slideFromRightPage(
                    state: state,
                    child: const TagGroupsScreen(),
                  ),
                ),
                GoRoute(
                  path: 'payment-methods',
                  pageBuilder: (context, state) => slideFromRightPage(
                    state: state,
                    child: const PaymentMethodsScreen(),
                  ),
                ),
                GoRoute(
                  path: 'events',
                  pageBuilder: (context, state) => slideFromRightPage(
                    state: state,
                    child: const EventsScreen(),
                  ),
                ),
                GoRoute(
                  path: 'projects',
                  pageBuilder: (context, state) => slideFromRightPage(
                    state: state,
                    child: const ProjectsScreen(),
                  ),
                ),
                GoRoute(
                  path: 'recurring',
                  pageBuilder: (context, state) => slideFromRightPage(
                    state: state,
                    child: const RecurringScreen(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    // Account hub — reached from the header gear on any tab. Pushed over the
    // shell (root navigator), so it is full-screen with a back button.
    GoRoute(
      path: '/account',
      pageBuilder: (context, state) => topDownPage(
        state: state,
        child: const AccountScreen(),
      ),
      routes: [
        GoRoute(
          path: 'profile',
          pageBuilder: (context, state) => slideFromRightPage(
            state: state,
            child: const ProfileScreen(),
          ),
        ),
        GoRoute(
          path: 'export',
          pageBuilder: (context, state) => slideFromRightPage(
            state: state,
            child: const ExportScreen(),
          ),
        ),
        GoRoute(
          path: 'backup',
          pageBuilder: (context, state) => slideFromRightPage(
            state: state,
            child: const BackupScreen(),
          ),
        ),
      ],
    ),
  ],
);

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/hairline_list_tile.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translationsAsync = ref.watch(translationsProvider);
    final t = translationsAsync.asData?.value;
    final pendingCount = ref.watch(pendingRecurringCountProvider).asData?.value ?? 0;

    final items = [
      (LucideIcons.repeat300, 'settings_nav.recurring', 'Recurring', '/settings/recurring'),
      (LucideIcons.gitBranch300, 'settings_nav.categories', 'Categories', '/settings/categories'),
      (LucideIcons.tag300, 'settings_nav.tags', 'Tags', '/settings/tags'),
      (LucideIcons.list300, 'settings_nav.tag_groups', 'Tag groups', '/settings/tag-groups'),
      (LucideIcons.creditCard300, 'settings_nav.payment_methods', 'Payment methods', '/settings/payment-methods'),
      (LucideIcons.calendar300, 'settings_nav.events', 'Events', '/settings/events'),
      (LucideIcons.fileText300, 'settings_nav.projects', 'Projects', '/settings/projects'),
    ];

    return Scaffold(
      body: Column(
        children: [
          AppTopBar(title: t?.t('nav.settings') ?? 'Settings'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
              children: [
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    children: [
                      for (final (index, (icon, key, fallback, path)) in items.indexed)
                        HairlineListTile(
                          icon: icon,
                          title: t?.t(key) ?? fallback,
                          trailing: (key == 'settings_nav.recurring' && pendingCount > 0)
                              ? _PendingBadge(count: pendingCount)
                              : null,
                          onTap: () => context.push(path),
                          showDivider: index != items.length - 1,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Accent pill showing the count of recurring occurrences awaiting confirmation.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Text(
        '$count',
        style: TextStyle(color: colors.onAccent, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

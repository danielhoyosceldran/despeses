import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/hairline_list_tile.dart';
import '../widgets/page_title_header.dart';

/// Account hub reached from the header gear: personal/app settings —
/// Profile, Export, Backup. Pushed over the shell (full-screen with back).
/// The catalog data (categories, tags, …) lives on the Settings tab instead.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).asData?.value;

    final items = [
      (LucideIcons.settings300, 'settings_nav.profile', 'Profile', '/account/profile'),
      (LucideIcons.download300, 'settings_nav.export', 'Export', '/account/export'),
    ];

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xxl),
        children: [
          PageTitleHeader(t?.t('nav.settings') ?? 'Settings'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (final (icon, key, fallback, path) in items)
                  HairlineListTile(
                    icon: icon,
                    title: t?.t(key) ?? fallback,
                    onTap: () => context.push(path),
                  ),
                HairlineListTile(
                  icon: LucideIcons.hardDriveDownload300,
                  title: 'Backup',
                  onTap: () => context.push('/account/backup'),
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

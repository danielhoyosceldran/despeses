import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/hairline_list_tile.dart';
import '../../widgets/page_title_header.dart';

/// Language, theme, and a read-only currency field (plan §3.8, §6): v1 only
/// supports EUR, so the currency-change warning/block logic has nothing to
/// react to yet — the field is shown read-only instead of a picker. There is
/// intentionally no primary-color selector (postponed).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  /// Native display name per supported locale (no i18n asset carries these).
  static const _languageNames = {
    'en': 'English',
    'es': 'Español',
    'ca': 'Català',
    'fr': 'Français',
    'it': 'Italiano',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileStreamProvider);
    final t = ref.watch(translationsProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(),
      body: profileAsync.when(
        data: (profile) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
          children: [
            PageTitleHeader(t?.t('settings_nav.profile') ?? 'Profile'),

            _SectionLabel(t?.t('profile.language') ?? 'Language'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              clip: true,
              child: Column(
                children: [
                  for (final (index, code) in Translations.supportedLocales.indexed)
                    _LanguageRow(
                      label: _languageNames[code] ?? code.toUpperCase(),
                      code: code,
                      selected: profile.language == code,
                      showDivider: index != Translations.supportedLocales.length - 1,
                      onTap: () => ref.read(profileRepositoryProvider).setLanguage(code),
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),
            _SectionLabel(t?.t('profile.theme') ?? 'Theme'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              clip: true,
              child: HairlineListTile(
                icon: LucideIcons.moon300,
                title: t?.t('profile.theme_dark') ?? 'Dark theme',
                showDivider: false,
                onTap: () => ref
                    .read(profileRepositoryProvider)
                    .setTheme(profile.theme == 'dark' ? 'light' : 'dark'),
                trailing: Switch(
                  value: profile.theme == 'dark',
                  activeThumbColor: context.appColors.accent,
                  onChanged: (value) =>
                      ref.read(profileRepositoryProvider).setTheme(value ? 'dark' : 'light'),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),
            _SectionLabel(t?.t('profile.currency') ?? 'Currency'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              clip: true,
              child: HairlineListTile(
                icon: LucideIcons.coins300,
                title: t?.t('profile.currency') ?? 'Currency',
                showDivider: false,
                trailing: Text(
                  profile.currency,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: context.appColors.textMuted,
                      ),
                ),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

/// Uppercase muted section header above a settings card.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.smMd),
      child: Text(text.toUpperCase(), style: appHeaderStyle(context.appColors)),
    );
  }
}

/// Single language option: label + trailing accent check when selected,
/// hairline divider between rows. Matches [HairlineListTile] metrics.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.code,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final String label;
  final String code;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smMd),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (selected) Icon(LucideIcons.check300, size: 20, color: colors.accent),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(color: colors.divider, height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
      ],
    );
  }
}

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/haptics.dart';
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
                    _OptionRow(
                      label: _languageNames[code] ?? code.toUpperCase(),
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
              child: Column(
                children: [
                  for (final (index, (value, fallback)) in const [
                    ('light', 'Light'),
                    ('dark', 'Dark'),
                    ('system', 'System'),
                  ].indexed)
                    _OptionRow(
                      label: t?.t('profile.theme_$value') ?? fallback,
                      selected: profile.theme == value,
                      showDivider: index != 2,
                      onTap: () => ref.read(profileRepositoryProvider).setTheme(value),
                    ),
                ],
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

            const SizedBox(height: AppSpacing.lg),
            _SectionLabel(t?.t('profile.feedback') ?? 'Feedback'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              clip: true,
              child: Column(
                children: [
                  _ToggleRow(
                    label: t?.t('profile.haptics') ?? 'Haptics',
                    value: profile.hapticsEnabled,
                    onChanged: (v) => ref.read(profileRepositoryProvider).setHapticsEnabled(v),
                  ),
                  Divider(color: context.appColors.divider, height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
                  _StrengthRow(
                    label: t?.t('profile.haptics_strength') ?? 'Strength',
                    levelLabels: [
                      t?.t('profile.haptics_soft') ?? 'Soft',
                      t?.t('profile.haptics_medium') ?? 'Medium',
                      t?.t('profile.haptics_strong') ?? 'Strong',
                    ],
                    value: profile.hapticsStrength,
                    enabled: profile.hapticsEnabled,
                    onChanged: (v) {
                      ref.read(profileRepositoryProvider).setHapticsStrength(v);
                      ref.read(hapticsProvider).medium();
                    },
                  ),
                ],
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

/// Label + trailing [Switch]. Matches [HairlineListTile] metrics.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
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
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.accent,
          ),
        ],
      ),
    );
  }
}

/// Label + 3-stop slider (Soft/Medium/Strong) for haptic intensity. Dimmed and
/// non-interactive when haptics are off. Matches [HairlineListTile] metrics.
class _StrengthRow extends StatelessWidget {
  const _StrengthRow({
    required this.label,
    required this.levelLabels,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final List<String> levelLabels;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final v = value.clamp(0, 2);
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                Text(
                  levelLabels[v],
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
            Slider(
              value: v.toDouble(),
              min: 0,
              max: 2,
              divisions: 2,
              activeColor: colors.accent,
              onChanged: enabled ? (d) => onChanged(d.round()) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Single selectable option: label + trailing accent check when selected,
/// hairline divider between rows. Matches [HairlineListTile] metrics.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final String label;
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

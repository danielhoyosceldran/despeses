import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/providers/app_providers.dart';

/// Language, theme, and a read-only currency field (plan §3.8, §6): v1 only
/// supports EUR, so the currency-change warning/block logic has nothing to
/// react to yet — the selector shows a single fixed option instead of a
/// picker. There is intentionally no primary-color selector (postponed).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translationsAsync = ref.watch(translationsProvider);
    final profileAsync = ref.watch(profileStreamProvider);
    final translations = translationsAsync.asData?.value;

    return Scaffold(
      appBar: AppBar(title: Text(translations?.t('settings_nav.profile') ?? 'Profile')),
      body: profileAsync.when(
        data: (profile) => ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Language', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final code in Translations.supportedLocales)
              RadioListTile<String>(
                title: Text(code),
                value: code,
                groupValue: profile.language,
                onChanged: (value) {
                  if (value != null) ref.read(profileRepositoryProvider).setLanguage(value);
                },
              ),
            const Divider(),
            SwitchListTile(
              title: const Text('Dark theme'),
              value: profile.theme == 'dark',
              onChanged: (value) {
                ref.read(profileRepositoryProvider).setTheme(value ? 'dark' : 'light');
              },
            ),
            const Divider(),
            ListTile(
              title: const Text('Currency'),
              trailing: Text(profile.currency),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

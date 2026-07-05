import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translationsAsync = ref.watch(translationsProvider);
    final t = translationsAsync.asData?.value;

    final items = [
      ('settings_nav.categories', 'Categories', '/settings/categories'),
      ('settings_nav.tags', 'Tags', '/settings/tags'),
      ('settings_nav.tag_groups', 'Tag groups', '/settings/tag-groups'),
      ('settings_nav.payment_methods', 'Payment methods', '/settings/payment-methods'),
      ('settings_nav.events', 'Events', '/settings/events'),
      ('settings_nav.projects', 'Projects', '/settings/projects'),
      ('settings_nav.profile', 'Profile', '/settings/profile'),
      ('settings_nav.export', 'Export', '/settings/export'),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(t?.t('nav.settings') ?? 'Settings')),
      body: ListView(
        children: [
          for (final (key, fallback, path) in items)
            ListTile(
              title: Text(t?.t(key) ?? fallback),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(path),
            ),
          ListTile(
            title: const Text('Backup'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/backup'),
          ),
        ],
      ),
    );
  }
}

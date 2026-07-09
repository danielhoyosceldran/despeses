import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/app_providers.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: DespesesApp()));
}

class DespesesApp extends ConsumerWidget {
  const DespesesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileStreamProvider);
    final locale = profileAsync.asData?.value.language;
    final themeMode = profileAsync.asData?.value.theme == 'dark' ? ThemeMode.dark : ThemeMode.light;

    return MaterialApp.router(
      title: 'canut finances',
      routerConfig: appRouter,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: locale == null ? null : Locale(locale),
      supportedLocales: const [
        Locale('en'),
        Locale('es'),
        Locale('ca'),
        Locale('fr'),
        Locale('it'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

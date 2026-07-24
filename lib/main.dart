import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/format/date.dart';
import 'core/format/money.dart';
import 'core/providers/app_providers.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Pre-load intl date symbols for every supported locale so `formatDate`
    // (R16) never hits an unloaded-locale exception on first use.
    await Future.wait(supportedDateLocales.map(initializeDateFormatting));

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      Zone.current.handleUncaughtError(details.exception, details.stack ?? StackTrace.empty);
    };

    if (!kDebugMode) {
      ErrorWidget.builder = (details) {
        return const Material(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Something went wrong. Please restart the app.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      };
    }

    runApp(const AppRestartScope(child: DespesesApp()));
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}

/// Hosts the [ProviderScope] behind a key that can be swapped to force a
/// full teardown/rebuild of every provider (R18). Used by the backup-restore
/// flow: closing the database file out from under live `watch*` streams
/// (analytics, dashboard, etc.) can throw, so instead the whole provider
/// tree — and every widget watching it — is torn down first, then the
/// caller's teardown callback runs (safe to touch the db file), then a fresh
/// [ProviderScope] is built.
class AppRestartScope extends StatefulWidget {
  const AppRestartScope({super.key, required this.child});

  final Widget child;

  static Future<void> restart(BuildContext context, Future<void> Function() teardown) {
    final state = context.findAncestorStateOfType<_AppRestartScopeState>()!;
    return state._restart(teardown);
  }

  @override
  State<AppRestartScope> createState() => _AppRestartScopeState();
}

class _AppRestartScopeState extends State<AppRestartScope> {
  Key? _scopeKey = UniqueKey();

  Future<void> _restart(Future<void> Function() teardown) async {
    setState(() => _scopeKey = null);
    // Let the frame commit so the old ProviderScope (and its providers'
    // onDispose hooks, e.g. the database close) actually run before the
    // teardown callback touches the underlying file.
    await Future<void>.delayed(Duration.zero);
    await teardown();
    if (mounted) setState(() => _scopeKey = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    if (_scopeKey == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return ProviderScope(key: _scopeKey, child: widget.child);
  }
}

class DespesesApp extends ConsumerWidget {
  const DespesesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileStreamProvider);
    final locale = profileAsync.asData?.value.language;
    // Keep money/date formatting in sync with the profile language (C1, R16).
    setMoneyLocale(locale);
    setDateLocale(locale);
    final themeMode = switch (profileAsync.asData?.value.theme) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };

    return MaterialApp.router(
      title: 'canut finances',
      debugShowCheckedModeBanner: false,
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

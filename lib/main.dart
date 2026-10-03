import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/format/date.dart';
import 'core/format/money.dart';
import 'core/providers/app_providers.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Nothing is awaited before runApp (BL-066): the profile, its translations
    // and its date symbols load while the native splash is still up, because
    // the first frame is held back until they are ready (see _FirstFrame).
    _FirstFrame.hold();

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

/// Holds the first frame back so the native splash stays up until the profile
/// and its translations are loaded: the first frame the user sees is already
/// in their language instead of flashing the English fallback texts (BL-066).
/// Released once — also when loading fails, or after [_timeout] at the latest,
/// so a broken load can never leave the app stuck on the splash.
abstract final class _FirstFrame {
  static const _timeout = Duration(seconds: 3);
  static bool _held = false;

  static void hold() {
    _held = true;
    WidgetsBinding.instance.deferFirstFrame();
    Timer(_timeout, release);
  }

  static void release() {
    if (!_held) return;
    _held = false;
    WidgetsBinding.instance.allowFirstFrame();
  }
}

class DespesesApp extends ConsumerWidget {
  const DespesesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileStreamProvider);
    final locale = profileAsync.asData?.value.language;
    final translations = ref.watch(translationsProvider);
    if (!translations.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _FirstFrame.release());
    }
    // Keep money/date formatting in sync with the profile language (C1, R16).
    // Dates switch with the loaded translations, whose provider has already
    // loaded that locale's date symbols.
    setMoneyLocale(locale);
    setDateLocale(translations.valueOrNull?.locale);
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

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

export 'app_colors.dart';
export 'app_dimens.dart';

/// Section/day header label style: uppercase, semibold, tracking-wide, muted
/// (the mock's `text-xs font-semibold uppercase tracking-wide`). Apply
/// `.toUpperCase()` to the text at the call site.
TextStyle appHeaderStyle(AppColors colors, {double fontSize = 12}) => TextStyle(
      fontFamily: 'Inter',
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: colors.textMuted,
    );

/// Display face for money and headlines (Clash Display), tracking-tight with
/// tabular figures. Use for balances, amounts, budget names, modal titles.
TextStyle appDisplay(
  AppColors colors, {
  required double fontSize,
  FontWeight fontWeight = FontWeight.w500,
  Color? color,
}) =>
    TextStyle(
      fontFamily: 'ClashDisplay',
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: -0.5,
      height: 1.0,
      color: color ?? colors.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Revolut-style theme: flat background, rounded cards with one soft shadow,
/// filled inputs without visible borders, pill chips, big bold titles.
class AppTheme {
  static ThemeData light() => _build(AppColors.light, AppSemanticColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, AppSemanticColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, AppSemanticColors semantic, Brightness brightness) {
    final textTheme = _textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.bg,
      extensions: [colors, semantic],
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: brightness,
        primary: colors.accent,
        surface: colors.surface,
        error: semantic.expense,
      ),
      fontFamily: 'Inter',
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: colors.divider,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SlideFadeTransitionsBuilder(),
          TargetPlatform.iOS: _SlideFadeTransitionsBuilder(),
          TargetPlatform.windows: _SlideFadeTransitionsBuilder(),
          TargetPlatform.macOS: _SlideFadeTransitionsBuilder(),
          TargetPlatform.linux: _SlideFadeTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusCard)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusCard)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: colors.textDisabled,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimens.radiusSheet)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        elevation: 0,
        indicatorColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: selected ? colors.accent : colors.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? colors.accent : colors.textMuted, size: 22);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.mutedFill(0.30), // bg-muted/30
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusButton),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusButton),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusButton),
          borderSide: BorderSide(color: colors.accent, width: 1.5),
        ),
        hintStyle: TextStyle(color: colors.textMuted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          minimumSize: const Size(64, AppDimens.buttonHeight),
          elevation: 0,
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusButton)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusButton)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide.none,
          backgroundColor: colors.mutedFill(0.5), // bg-muted/50 track
          selectedBackgroundColor: colors.surface, // active segment = bg-card
          foregroundColor: colors.textMuted,
          selectedForegroundColor: colors.text,
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusPill)),
        side: BorderSide.none,
        backgroundColor: colors.surfaceAlt,
        selectedColor: pillBackground(colors.accent),
        checkmarkColor: colors.accent,
        labelStyle: TextStyle(color: colors.text),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceAlt,
        contentTextStyle: TextStyle(color: colors.text),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusButton)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.surfaceAlt,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        // Circular FAB (mock `rounded-full`). Shadow + scale-on-press are added
        // by the FAB wrapper widget, not the theme.
        shape: const CircleBorder(),
      ),
    );
  }

  // Two-tier type: Clash Display for money/headlines (display* + headline* +
  // titleLarge), Inter for UI/body. Money-bearing display styles carry tabular
  // figures. UI weight is predominantly medium (500), per the mock.
  static TextTheme _textTheme(AppColors colors) {
    return TextTheme(
      displayLarge: appDisplay(colors, fontSize: 60), // balance hero (expanded)
      displayMedium: appDisplay(colors, fontSize: 48), // analytics total
      displaySmall: appDisplay(colors, fontSize: 34), // keypad / big totals
      headlineMedium: appDisplay(colors, fontSize: 28),
      headlineSmall: appDisplay(colors, fontSize: 22),
      titleLarge: appDisplay(colors, fontSize: 20), // display section titles
      titleMedium: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w500, color: colors.text, height: 1.5),
      labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: colors.text, height: 1.5),
      bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w400, color: colors.text, height: 1.5),
      bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w400, color: colors.textMuted, height: 1.5),
      labelSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colors.textMuted,
      ),
    );
  }
}

/// Horizontal slide + fade for route changes (200–300ms feel, easeOutCubic).
class _SlideFadeTransitionsBuilder extends PageTransitionsBuilder {
  const _SlideFadeTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppDimens.animCurve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

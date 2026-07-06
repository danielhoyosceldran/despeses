import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

export 'app_colors.dart';
export 'app_dimens.dart';

/// Section/page header label style. Kept as a helper because it is used
/// across screens; now plain Inter (mono accent removed with the redesign).
TextStyle appHeaderStyle(AppColors colors, {double fontSize = 13}) => TextStyle(
      fontFamily: 'Inter',
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      color: colors.textMuted,
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
            fontSize: 11,
            fontWeight: FontWeight.w600,
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
        fillColor: colors.surfaceAlt,
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
          textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
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
          backgroundColor: colors.surfaceAlt,
          selectedBackgroundColor: colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusPill)),
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
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimens.radiusButton)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.surfaceAlt,
      ),
    );
  }

  static TextTheme _textTheme(AppColors colors) {
    return TextTheme(
      displaySmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: colors.text,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineMedium: TextStyle(fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w700, color: colors.text),
      headlineSmall: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700, color: colors.text),
      titleLarge: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w700, color: colors.text),
      titleMedium: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600, color: colors.text),
      labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: colors.text),
      bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w400, color: colors.text),
      bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w400, color: colors.textMuted),
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

import 'package:flutter/material.dart';

/// Design tokens from `plan/STYLE_FLUTTER.md`: straight corners everywhere,
/// hairline borders used sparingly, zero elevation, a single accent (the
/// web's 3-color picker is postponed — plan §6).
class AppColors {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.divider,
    required this.text,
    required this.textMuted,
    required this.textDisabled,
    required this.accent,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color divider;
  final Color text;
  final Color textMuted;
  final Color textDisabled;
  final Color accent;

  static const light = AppColors(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF5F6F7),
    border: Color(0xFFECECEC),
    divider: Color(0xFFF0F0F0),
    text: Color(0xFF1A1A1A),
    textMuted: Color(0xFF6B7280),
    textDisabled: Color(0xFFB0B4BB),
    accent: Color(0xFF2563EB),
  );

  static const dark = AppColors(
    bg: Color(0xFF0A0A0A),
    surface: Color(0xFF111111),
    surfaceAlt: Color(0xFF1A1A1A),
    border: Color(0xFF1E1E1E),
    divider: Color(0xFF181818),
    text: Color(0xFFF2F2F2),
    textMuted: Color(0xFF9A9A9A),
    textDisabled: Color(0xFF555555),
    accent: Color(0xFF5B8DEF),
  );
}

/// Semantic colors (functional, not decorative — plan §2): used only on the
/// specific amount/element they describe, never as fills or borders.
class AppSemanticColors {
  const AppSemanticColors({required this.income, required this.expense, required this.refund, required this.over});

  final Color income;
  final Color expense;
  final Color refund;
  final Color over;

  static const light = AppSemanticColors(
    income: Color(0xFF2A7057),
    expense: Color(0xFFA83232),
    refund: Color(0xFFA8621A),
    over: Color(0xFFA83232),
  );

  static const dark = AppSemanticColors(
    income: Color(0xFF4FA88A),
    expense: Color(0xFFD07070),
    refund: Color(0xFFD0954F),
    over: Color(0xFFD07070),
  );
}

/// Fixed 4·8·12·16·24·32·48·64 spacing scale (plan §4) — space is the
/// primary separator, borders are used only where space alone isn't enough.
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const smMd = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const xxxl = 64.0;
}

class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final textTheme = _textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: brightness,
        primary: colors.accent,
        surface: colors.surface,
      ),
      fontFamily: 'Inter',
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: colors.divider,
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bg,
        foregroundColor: colors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        elevation: 0,
        indicatorColor: colors.surfaceAlt,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: colors.accent, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: BorderSide(color: colors.border),
        backgroundColor: colors.surfaceAlt,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceAlt,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: colors.border),
        ),
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
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: colors.text,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineMedium: TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w700, color: colors.text),
      titleLarge: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600, color: colors.text),
      titleMedium: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: colors.text),
      headlineSmall: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600, color: colors.text),
      labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: colors.text),
      bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400, color: colors.text),
      bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w400, color: colors.textMuted),
      labelSmall: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: colors.textMuted,
      ),
    );
  }
}

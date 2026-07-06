import 'package:flutter/material.dart';

/// Revolut-style fintech palette. Registered as a [ThemeExtension] so widgets
/// read the active variant with `context.appColors` instead of branching on
/// brightness at every call site.
class AppColors extends ThemeExtension<AppColors> {
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
    required this.onAccent,
    required this.shadow,
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

  /// Foreground color for content sitting on [accent] fills.
  final Color onAccent;

  /// Card shadow color — pre-baked opacity (6% black light / 40% black dark).
  final Color shadow;

  static const light = AppColors(
    bg: Color(0xFFF7F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF0F1F5),
    border: Color(0xFFE8E9F0),
    divider: Color(0xFFEEEFF4),
    text: Color(0xFF191C32),
    textMuted: Color(0xFF8E90A6),
    textDisabled: Color(0xFFBDBFCE),
    accent: Color(0xFF5A31F4),
    onAccent: Color(0xFFFFFFFF),
    shadow: Color(0x0F000000),
  );

  static const dark = AppColors(
    bg: Color(0xFF0D0E12),
    surface: Color(0xFF1A1B23),
    surfaceAlt: Color(0xFF23242E),
    border: Color(0xFF262733),
    divider: Color(0xFF22232C),
    text: Color(0xFFF2F3F7),
    textMuted: Color(0xFF6E7085),
    textDisabled: Color(0xFF4A4B5A),
    accent: Color(0xFF7C5CFF),
    onAccent: Color(0xFFFFFFFF),
    shadow: Color(0x66000000),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? divider,
    Color? text,
    Color? textMuted,
    Color? textDisabled,
    Color? accent,
    Color? onAccent,
    Color? shadow,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textDisabled: textDisabled ?? this.textDisabled,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// Semantic colors tied to financial meaning (income/expense/refund/over),
/// not generic UI states. Same values in both themes; used only on the
/// specific amount/element they describe, never as large fills.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.income,
    required this.expense,
    required this.refund,
    required this.over,
  });

  final Color income;
  final Color expense;
  final Color refund;
  final Color over;

  static const light = AppSemanticColors(
    income: Color(0xFF00C48C),
    expense: Color(0xFFFF4757),
    refund: Color(0xFFFFB020),
    over: Color(0xFFFF4757),
  );

  static const dark = light;

  @override
  AppSemanticColors copyWith({Color? income, Color? expense, Color? refund, Color? over}) {
    return AppSemanticColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      refund: refund ?? this.refund,
      over: over ?? this.over,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      refund: Color.lerp(refund, other.refund, t)!,
      over: Color.lerp(over, other.over, t)!,
    );
  }
}

/// Pill/chip treatment: semantic color at 15% opacity as background with the
/// full color as foreground.
Color pillBackground(Color semantic) => semantic.withValues(alpha: 0.15);

extension AppThemeContext on BuildContext {
  /// Falls back on brightness when the extension is missing (e.g. widgets
  /// pumped under a vanilla [ThemeData] in tests).
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ??
      (Theme.of(this).brightness == Brightness.dark ? AppColors.dark : AppColors.light);

  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.light;
}

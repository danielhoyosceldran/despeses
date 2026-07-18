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

  /// Card shadow color — pre-baked opacity (12% black light / 40% black dark).
  final Color shadow;

  /// Hairline divider — [border] at 50% of its current alpha (the mock's
  /// default `border/50`). Use for card outlines, row separators, inputs.
  Color get borderSoft => border.withValues(alpha: border.a * 0.5);

  /// Translucent muted fill (`bg-muted/30|50|80`): stat tiles, form fields,
  /// search pill, the active nav pill.
  Color mutedFill([double opacity = 0.3]) => surfaceAlt.withValues(alpha: opacity);

  // Mono-ink palette from the "Innovative Style Proposal" mock (theme.css).
  // Neutral oklch(L 0 0) grays converted to sRGB. Accent is near-black ink in
  // light and inverts to near-white in dark. Borders stay translucent so the
  // 50% "hairline" (divider / borderSoft) reads correctly over any surface.
  static const light = AppColors(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFECECF0), // --muted
    border: Color(0x1A000000), // rgba(0,0,0,0.10)
    divider: Color(0x0D000000), // border at 50% → rgba(0,0,0,0.05)
    text: Color(0xFF252525), // --foreground oklch(0.145)
    textMuted: Color(0xFF717182), // --muted-foreground
    textDisabled: Color(0xFFB0B1BC),
    accent: Color(0xFF030213), // --primary (ink)
    onAccent: Color(0xFFFFFFFF),
    shadow: Color(0x1F000000), // 12% black
  );

  static const dark = AppColors(
    bg: Color(0xFF0D0D0D), // near-black base
    surface: Color(0xFF161616), // raised surface reads above bg
    surfaceAlt: Color(0xFF262626), // --muted
    border: Color(0xFF2E2E2E),
    divider: Color(0x802E2E2E), // border at 50%
    text: Color(0xFFFAFAFA), // --foreground oklch(0.985)
    textMuted: Color(0xFFB5B5B5), // --muted-foreground oklch(0.708)
    textDisabled: Color(0xFF7F7F7F), // oklch(0.5)
    accent: Color(0xFFFAFAFA), // --primary inverts to near-white
    onAccent: Color(0xFF161616), // sits on near-white accent
    shadow: Color(0x99000000), // 60% black — deeper on darker bg
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
    required this.savings,
    required this.over,
  });

  final Color income;
  final Color expense;
  final Color refund;
  final Color savings;
  final Color over;

  // Tailwind 500 palette from the mock. Refund is rendered in the neutral text
  // color (see AmountText), so this value is a fallback only.
  static const light = AppSemanticColors(
    income: Color(0xFF10B981), // emerald 500
    expense: Color(0xFFF43F5E), // rose 500
    refund: Color(0xFFF59E0B), // amber 500 (fallback; refund shown neutral)
    savings: Color(0xFF3B82F6), // blue 500 (savings = money set aside, not spent)
    over: Color(0xFFF43F5E), // rose 500
  );

  static const dark = light;

  @override
  AppSemanticColors copyWith({Color? income, Color? expense, Color? refund, Color? savings, Color? over}) {
    return AppSemanticColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      refund: refund ?? this.refund,
      savings: savings ?? this.savings,
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
      savings: Color.lerp(savings, other.savings, t)!,
      over: Color.lerp(over, other.over, t)!,
    );
  }
}

/// Pill/chip treatment: semantic color at 15% opacity as background with the
/// full color as foreground.
Color pillBackground(Color semantic) => semantic.withValues(alpha: 0.15);

/// Colored icon-chip fill from the mock: data color at 10% opacity, full color
/// as the icon tint (e.g. `bg-emerald-500/10`).
Color iconChipBackground(Color c) => c.withValues(alpha: 0.10);

/// Data-accent palette (Tailwind 500). Used only for category icon chips,
/// budget progress fills and donut slices — never as a UI surface fill.
class AppDataColors {
  const AppDataColors._();
  static const emerald = Color(0xFF10B981);
  static const rose = Color(0xFFF43F5E);
  static const purple = Color(0xFF8B5CF6);
  static const amber = Color(0xFFF59E0B);
  static const blue = Color(0xFF3B82F6);

  /// Cycle used when assigning colors to budgets/series without an explicit one.
  static const cycle = [emerald, purple, amber, blue, rose];
}

extension AppThemeContext on BuildContext {
  /// Falls back on brightness when the extension is missing (e.g. widgets
  /// pumped under a vanilla [ThemeData] in tests).
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ??
      (Theme.of(this).brightness == Brightness.dark ? AppColors.dark : AppColors.light);

  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.light;

  /// Amount color by transaction type. Income = emerald, expense = rose,
  /// **refund = neutral foreground** (per the mock — no dedicated color),
  /// savings = blue (money set aside, not spent).
  Color amountColorForType(String type) => switch (type) {
        'income' => semanticColors.income,
        'refund' => appColors.text,
        'ahorro' => semanticColors.savings,
        _ => semanticColors.expense,
      };
}

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Big amount display split into integer/decimal spans — integer full
/// weight, decimals smaller and muted — matching the mockups' "1,234.56".
class AmountText extends StatelessWidget {
  const AmountText({super.key, required this.amountCents, this.currency, this.color, this.style});

  final int amountCents;
  final String? currency;
  final Color? color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;
    final base = style ?? Theme.of(context).textTheme.displaySmall!;
    final parts = (amountCents / 100).toStringAsFixed(2).split('.');
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: parts[0],
            style: base.copyWith(color: color ?? colors.text, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          TextSpan(
            text: '.${parts[1]}${currency == null ? '' : ' $currency'}',
            style: base.copyWith(
              color: colors.textMuted,
              fontSize: (base.fontSize ?? 32) * 0.55,
              fontWeight: FontWeight.w400,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

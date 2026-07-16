import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';

/// Big amount display split into integer/decimal spans — integer full
/// weight, decimals (and any trailing currency symbol) smaller and muted.
/// Locale-aware (C1): uses [formatMoney]/[formatDecimal] and splits on the
/// locale's decimal separator, so `es` renders `1.234` big + `,56 €` small.
class AmountText extends StatelessWidget {
  const AmountText({super.key, required this.amountCents, this.currency, this.color, this.style});

  final int amountCents;
  final String? currency;
  final Color? color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final base = style ?? Theme.of(context).textTheme.displaySmall!;
    final text = currency == null ? formatDecimal(amountCents) : formatMoney(amountCents, currency!);
    final sep = decimalSeparatorFor();
    final idx = text.lastIndexOf(sep);
    final intPart = idx < 0 ? text : text.substring(0, idx);
    final fracPart = idx < 0 ? '' : text.substring(idx);
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: intPart,
            style: base.copyWith(color: color ?? colors.text, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          TextSpan(
            text: fracPart,
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

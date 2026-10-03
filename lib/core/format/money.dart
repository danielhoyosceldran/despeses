import 'package:intl/intl.dart';

/// Single, locale-aware money formatter (C1) — replaces the `toStringAsFixed(2)
/// + currency code` string that was copy-pasted across 6+ widgets.
///
/// Formats integer cents with the locale's grouping/decimal separators and the
/// currency's *symbol*, e.g. `formatMoney(123456, 'EUR')` → `1.234,56 €` under
/// `es`, `€1,234.56` under `en`.
///
/// The active locale is kept module-level (updated by the app root via
/// [setMoneyLocale]) instead of being threaded through every call site, so the
/// helper stays a drop-in for the old `formatAmount(cents, currency)`.
String _moneyLocale = 'en';

/// The locale money is currently formatted in. Kept in sync with the profile
/// language by the app root.
String get moneyLocale => _moneyLocale;

/// Sets the active money-formatting locale (no-op for null/empty).
void setMoneyLocale(String? locale) {
  if (locale != null && locale.isNotEmpty) _moneyLocale = locale;
}

/// Formatters are cached by locale (and currency): building a [NumberFormat]
/// parses its pattern and symbols, and these helpers run per list row and per
/// animation frame (BL-059). Keyed by locale, so no invalidation is needed when
/// [setMoneyLocale] changes it. Reuse is safe: `format` is synchronous.
final _currencyFormats = <String, NumberFormat>{};
final _decimalFormats = <String, NumberFormat>{};

/// Throws (and caches nothing) for a currency code `intl` doesn't know.
NumberFormat _currencyFormat(String currency, String? locale) {
  final loc = locale ?? _moneyLocale;
  return _currencyFormats.putIfAbsent(
      '$loc|$currency', () => NumberFormat.simpleCurrency(locale: loc, name: currency));
}

NumberFormat _decimalFormat(String? locale) {
  final loc = locale ?? _moneyLocale;
  return _decimalFormats.putIfAbsent(
      loc, () => NumberFormat.decimalPatternDigits(locale: loc, decimalDigits: 2));
}

/// Cents → localized amount with the currency symbol.
///
/// `simpleCurrency` throws for a currency code `intl` doesn't know (only
/// reachable through a corrupt import/restore, since the UI has no free-form
/// currency input). Fall back to `<amount> <code>` instead of crashing the
/// widget that renders the amount.
String formatMoney(int cents, String currency, {String? locale}) {
  try {
    return _currencyFormat(currency, locale).format(cents / 100);
  } catch (_) {
    return '${formatDecimal(cents, locale: locale)} $currency';
  }
}

/// Cents → localized plain number (2 decimals, no currency symbol). Used where
/// the symbol is shown separately (e.g. split-styled displays).
String formatDecimal(int cents, {String? locale}) => _decimalFormat(locale).format(cents / 100);

/// The locale's decimal separator (`.` for en, `,` for es), so a split-styled
/// renderer can find the fractional boundary of [formatMoney]'s output.
String decimalSeparatorFor({String? locale}) => _decimalFormat(locale).symbols.DECIMAL_SEP;

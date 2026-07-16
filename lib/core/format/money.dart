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

NumberFormat _currencyFormat(String currency, String? locale) =>
    NumberFormat.simpleCurrency(locale: locale ?? _moneyLocale, name: currency);

/// Cents → localized amount with the currency symbol.
String formatMoney(int cents, String currency, {String? locale}) =>
    _currencyFormat(currency, locale).format(cents / 100);

/// Cents → localized plain number (2 decimals, no currency symbol). Used where
/// the symbol is shown separately (e.g. split-styled displays).
String formatDecimal(int cents, {String? locale}) =>
    NumberFormat.decimalPatternDigits(locale: locale ?? _moneyLocale, decimalDigits: 2)
        .format(cents / 100);

/// The locale's decimal separator (`.` for en, `,` for es), so a split-styled
/// renderer can find the fractional boundary of [formatMoney]'s output.
String decimalSeparatorFor({String? locale}) =>
    NumberFormat.decimalPatternDigits(locale: locale ?? _moneyLocale, decimalDigits: 2)
        .symbols
        .DECIMAL_SEP;

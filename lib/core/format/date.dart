import 'package:intl/intl.dart';

/// Single, locale-aware date formatter (R16) — replaces the raw
/// `DateTime.toString().split(' ').first` / manual `yyyy-MM-dd` string
/// building that was copy-pasted across filter sheets and form dialogs.
///
/// The active locale is kept module-level (updated by the app root via
/// [setDateLocale]) instead of being threaded through every call site,
/// mirroring [setMoneyLocale] in `money.dart`.
/// Locales `initializeDateFormatting` must load before [formatDate] or
/// [formatMonthAbbrev] can be used with them — kept in sync with
/// `Translations.supportedLocales`.
const supportedDateLocales = ['en', 'es', 'ca', 'fr', 'it'];

String _dateLocale = 'en';

/// The locale dates are currently formatted in. Kept in sync with the
/// profile language by the app root.
String get dateLocale => _dateLocale;

/// Sets the active date-formatting locale (no-op for null/empty).
void setDateLocale(String? locale) {
  if (locale != null && locale.isNotEmpty) _dateLocale = locale;
}

/// Short localized date, e.g. `24/07/2026` (es) or `7/24/2026` (en).
String formatDate(DateTime d, {String? locale}) =>
    DateFormat.yMd(locale ?? _dateLocale).format(d);

/// Localized month abbreviation, e.g. `jul.` (es) or `Jul` (en).
String formatMonthAbbrev(int year, int month, {String? locale}) =>
    DateFormat.MMM(locale ?? _dateLocale).format(DateTime(year, month));

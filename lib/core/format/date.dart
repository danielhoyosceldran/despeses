import 'package:intl/date_symbol_data_local.dart';
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

final _loadedDateLocales = <String>{};

/// Loads the intl date symbols of [locale] (once). Only the profile's locale
/// is loaded at startup; another one is loaded when the user switches to it
/// (BL-066), before [setDateLocale] activates it.
Future<void> ensureDateLocale(String locale) async {
  final code = supportedDateLocales.contains(locale) ? locale : supportedDateLocales.first;
  if (_loadedDateLocales.contains(code)) return;
  await initializeDateFormatting(code);
  _loadedDateLocales.add(code);
}

String _dateLocale = 'en';

/// The locale dates are currently formatted in. Kept in sync with the
/// profile language by the app root.
String get dateLocale => _dateLocale;

/// Sets the active date-formatting locale (no-op for null/empty).
void setDateLocale(String? locale) {
  if (locale != null && locale.isNotEmpty) _dateLocale = locale;
}

final _dateFormats = <String, DateFormat>{};

/// Cached [DateFormat] for an intl [skeleton] (`yMd`, `MMMEd`, `yMMMM`, ...).
/// Building one parses its pattern, and list rows / day headers format a date
/// per item on every build (BL-059). A null [locale] resolves like intl does
/// (`Intl.getCurrentLocale()`), so this is a drop-in for `DateFormat.xxx()`.
DateFormat cachedDateFormat(String skeleton, {String? locale}) {
  final loc = locale ?? Intl.getCurrentLocale();
  return _dateFormats.putIfAbsent('$loc|$skeleton', () => DateFormat(skeleton, loc));
}

/// Short localized date, e.g. `24/07/2026` (es) or `7/24/2026` (en).
String formatDate(DateTime d, {String? locale}) =>
    cachedDateFormat(DateFormat.YEAR_NUM_MONTH_DAY, locale: locale ?? _dateLocale).format(d);

/// Localized month abbreviation, e.g. `jul.` (es) or `Jul` (en).
String formatMonthAbbrev(int year, int month, {String? locale}) =>
    cachedDateFormat(DateFormat.ABBR_MONTH, locale: locale ?? _dateLocale).format(DateTime(year, month));

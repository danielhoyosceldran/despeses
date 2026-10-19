import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Loads the 5 locale JSON assets (ported as-is from `gastos/src/locales/`)
/// and resolves dotted keys (`category.food`) against nested maps.
///
/// A dynamic string-keyed lookup is required because defaults such as
/// `category.food` or `tag_group.ungrouped` are stored in the database and
/// resolved at render time — this cannot be expressed with generated ARB/
/// gen-l10n classes (plan §6).
class Translations {
  /// [values] is the nested JSON map; it is flattened once into dotted keys
  /// so [t] is a single hash lookup instead of a split + nested walk per call
  /// (it runs hundreds of times per build — BL-069).
  Translations(Map<String, dynamic> values, {this.locale = fallbackLocale}) : _flat = _flatten(values);

  final Map<String, String> _flat;

  /// The locale these strings are in.
  final String locale;

  static Map<String, String> _flatten(Map<String, dynamic> values) {
    final out = <String, String>{};
    void walk(Map<String, dynamic> node, String prefix) {
      node.forEach((key, value) {
        final path = prefix.isEmpty ? key : '$prefix.$key';
        if (value is String) {
          out[path] = value;
        } else if (value is Map<String, dynamic>) {
          walk(value, path);
        }
      });
    }

    walk(values, '');
    return out;
  }

  static const supportedLocales = ['en', 'es', 'ca', 'fr', 'it'];
  static const fallbackLocale = 'en';

  static Future<Translations> load(String locale) async {
    final code = supportedLocales.contains(locale) ? locale : fallbackLocale;
    final raw = await rootBundle.loadString('assets/locales/$code.json');
    return Translations(jsonDecode(raw) as Map<String, dynamic>, locale: code);
  }

  /// Resolves a dotted [key] (e.g. `category.food`); returns [key] itself if
  /// not found, so a missing translation is visible instead of crashing.
  String t(String key) => _flat[key] ?? key;
}

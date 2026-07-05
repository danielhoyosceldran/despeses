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
  Translations(this._values);

  final Map<String, dynamic> _values;

  static const supportedLocales = ['en', 'es', 'ca', 'fr', 'it'];
  static const fallbackLocale = 'en';

  static Future<Translations> load(String locale) async {
    final code = supportedLocales.contains(locale) ? locale : fallbackLocale;
    final raw = await rootBundle.loadString('assets/locales/$code.json');
    return Translations(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Resolves a dotted [key] (e.g. `category.food`); returns [key] itself if
  /// not found, so a missing translation is visible instead of crashing.
  String t(String key) {
    dynamic node = _values;
    for (final part in key.split('.')) {
      if (node is Map<String, dynamic> && node.containsKey(part)) {
        node = node[part];
      } else {
        return key;
      }
    }
    return node is String ? node : key;
  }
}

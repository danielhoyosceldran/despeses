import 'translations.dart';

/// `displayName` rule (plan §8): defaults are stored as i18n keys and
/// translated at render time; once a default is renamed it becomes free text
/// (`is_default = false`) and is shown as-is.
String displayNameFor(Translations t, {required String name, required bool isDefault}) {
  return isDefault ? t.t(name) : name;
}

/// `tag_groups` has no `is_default` column (plan §2) — defaults are detected
/// by the `tag_group.` prefix instead.
String tagGroupDisplayName(Translations t, String name) {
  return name.startsWith('tag_group.') ? t.t(name) : name;
}

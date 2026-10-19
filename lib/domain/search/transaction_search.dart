import '../../data/database.dart';

/// Comparison applied to a transaction's amount by an amount filter token.
enum AmountOp { eq, neq, lt, lte, gt, gte }

/// A single amount condition, e.g. `>50` → (gt, 5000 cents).
class AmountFilter {
  const AmountFilter(this.op, this.cents);

  final AmountOp op;
  final int cents;

  bool matches(int amount) => switch (op) {
    AmountOp.eq => amount == cents,
    AmountOp.neq => amount != cents,
    AmountOp.lt => amount < cents,
    AmountOp.lte => amount <= cents,
    AmountOp.gt => amount > cents,
    AmountOp.gte => amount >= cents,
  };
}

/// Parsed free-form transaction search (Transactions tab search box).
///
/// Whitespace-separated tokens, all of which must match (AND):
/// - `>50`, `<20`, `>=10`, `<=10`, `=12,5`, `!=3` → amount comparison. The
///   amount is the absolute value (no sign); `,` or `.` work as decimal mark.
/// - a bare number (`12,50`) → matches the exact amount **or** the text.
/// - anything else → case- and accent-insensitive substring of the title
///   (description) or notes.
class TransactionQuery {
  TransactionQuery._(this.terms, this.amountFilters, this.numericTerms);

  /// Folded text terms, matched against title + notes.
  final List<String> terms;
  final List<AmountFilter> amountFilters;

  /// Bare numbers: (folded text, cents) — match either the text or the amount.
  final List<(String, int)> numericTerms;

  bool get isEmpty => terms.isEmpty && amountFilters.isEmpty && numericTerms.isEmpty;

  static final RegExp _opToken = RegExp(r'^(>=|<=|!=|<>|=|>|<)\s*(.+)$');

  factory TransactionQuery.parse(String input) {
    final terms = <String>[];
    final filters = <AmountFilter>[];
    final numeric = <(String, int)>[];
    // Glue a detached operator to its number ("> 50" → ">50").
    final normalized = input.trim().replaceAllMapped(RegExp(r'(>=|<=|!=|<>|=|>|<)\s+'), (m) => m[1]!);
    for (final token in normalized.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final opMatch = _opToken.firstMatch(token);
      if (opMatch != null) {
        final cents = parseAmountCents(opMatch[2]!);
        if (cents != null) {
          filters.add(AmountFilter(_opFor(opMatch[1]!), cents));
          continue;
        }
      }
      final cents = parseAmountCents(token);
      if (cents != null) {
        numeric.add((foldForSearch(token), cents));
        continue;
      }
      terms.add(foldForSearch(token));
    }
    return TransactionQuery._(terms, filters, numeric);
  }

  static AmountOp _opFor(String op) => switch (op) {
    '>=' => AmountOp.gte,
    '<=' => AmountOp.lte,
    '!=' || '<>' => AmountOp.neq,
    '>' => AmountOp.gt,
    '<' => AmountOp.lt,
    _ => AmountOp.eq,
  };

  bool matches(Expense expense) {
    if (isEmpty) return true;
    for (final filter in amountFilters) {
      if (!filter.matches(expense.amount)) return false;
    }
    final haystack = foldForSearch('${expense.description ?? ''}\n${expense.notes ?? ''}');
    for (final term in terms) {
      if (!haystack.contains(term)) return false;
    }
    for (final (text, cents) in numericTerms) {
      if (expense.amount != cents && !haystack.contains(text)) return false;
    }
    return true;
  }
}

/// Parses a user-typed amount ("12", "12,5", "12.50", "1.234,56", "€30") into
/// cents, or null when it isn't a number. With both separators present the
/// last one is the decimal mark; a single separator followed by 1–2 digits is
/// decimal, otherwise it's a thousands separator.
int? parseAmountCents(String raw) {
  var s = raw.replaceAll(RegExp(r'[\s€$£¥]'), '');
  if (s.isEmpty || !RegExp(r'^[0-9.,]+$').hasMatch(s) || !RegExp(r'[0-9]').hasMatch(s)) return null;
  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  final decimalAt = lastDot > lastComma ? lastDot : lastComma;
  String intPart;
  var fracPart = '';
  if (decimalAt >= 0) {
    final after = s.substring(decimalAt + 1);
    final bothUsed = lastDot >= 0 && lastComma >= 0;
    if (bothUsed || (after.length <= 2 && s.indexOf(s[decimalAt]) == decimalAt)) {
      intPart = s.substring(0, decimalAt).replaceAll(RegExp(r'[.,]'), '');
      fracPart = after;
    } else {
      intPart = s.replaceAll(RegExp(r'[.,]'), '');
    }
  } else {
    intPart = s;
  }
  if (fracPart.length > 2 || fracPart.contains(RegExp(r'[.,]'))) return null;
  final whole = int.tryParse(intPart.isEmpty ? '0' : intPart);
  if (whole == null) return null;
  final frac = fracPart.isEmpty ? 0 : int.parse(fracPart.padRight(2, '0'));
  return whole * 100 + frac;
}

const Map<String, String> _accentMap = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

/// Lowercases and strips the common Latin accents so "cafe" finds "Café".
String foldForSearch(String input) {
  var s = input.toLowerCase();
  if (s.contains('l·l')) s = s.replaceAll('l·l', 'll');
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_accentMap[ch] ?? ch);
  }
  return buffer.toString();
}

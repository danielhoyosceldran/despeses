import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format/date.dart';
import '../../core/format/money.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';

/// Shared pieces of the "transactions grouped by day" lists (Dashboard month
/// pages, Transactions tab): the flattened lazy-list items, the per-day header
/// and the results summary header.

/// One day of transactions; [total] is the signed net in the profile currency.
class DayGroup {
  DayGroup(this.label);
  final String label;
  final List<Expense> items = [];
  int total = 0;
}

/// Marker item: vertical gap after the last row of a day group.
const dayGroupGap = Object();

/// Signed contribution to a net: income and refunds add, the rest subtracts.
int signedCents(Expense e) => switch (e.type) {
      'income' => e.amount,
      'refund' => e.amount,
      _ => -e.amount,
    };

/// [cents] with an explicit `+` when positive.
String formatSigned(int cents, String currency) {
  final sign = cents > 0 ? '+' : '';
  return '$sign${formatMoney(cents, currency)}';
}

/// "TODAY" / "YESTERDAY" / "WED, OCT 1". With [yearIfNotCurrent], days of
/// another year also carry the year, for lists that span several years.
String dayLabel(DateTime date, Translations? translations, {bool yearIfNotCurrent = false}) {
  final now = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return (translations?.t('dashboard.today') ?? 'Today').toUpperCase();
  if (diff == 1) return (translations?.t('dashboard.yesterday') ?? 'Yesterday').toUpperCase();
  final pattern = yearIfNotCurrent && date.year != now.year
      ? DateFormat.YEAR_ABBR_MONTH_WEEKDAY_DAY
      : DateFormat.ABBR_MONTH_WEEKDAY_DAY;
  return cachedDateFormat(pattern).format(date).toUpperCase();
}

/// Groups [expenses] (already sorted newest first) by calendar day.
List<DayGroup> groupByDay(
  List<Expense> expenses,
  String currency,
  Translations? translations, {
  bool yearIfNotCurrent = false,
}) {
  final groups = <DayGroup>[];
  final index = <String, int>{};
  for (final e in expenses) {
    final key = '${e.date.year}-${e.date.month}-${e.date.day}';
    var i = index[key];
    if (i == null) {
      i = groups.length;
      index[key] = i;
      groups.add(DayGroup(dayLabel(e.date, translations, yearIfNotCurrent: yearIfNotCurrent)));
    }
    groups[i].items.add(e);
    if (e.currency == currency) groups[i].total += signedCents(e);
  }
  return groups;
}

/// Flattened items for a lazy list: per day, its [DayGroup] header, then its
/// [Expense] rows, then [dayGroupGap].
List<Object> dayGroupedItems(
  List<Expense> expenses,
  String currency,
  Translations? translations, {
  bool yearIfNotCurrent = false,
}) {
  final items = <Object>[];
  for (final group in groupByDay(expenses, currency, translations, yearIfNotCurrent: yearIfNotCurrent)) {
    items
      ..add(group)
      ..addAll(group.items)
      ..add(dayGroupGap);
  }
  return items;
}

/// Per-day header: uppercase day label (left) + signed day total (right).
class DayGroupHeader extends StatelessWidget {
  const DayGroupHeader({super.key, required this.group, required this.currency});

  final DayGroup group;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.xs, AppSpacing.smMd),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(group.label, style: appHeaderStyle(colors)),
          Text(
            formatSigned(group.total, currency),
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: group.total >= 0 ? context.semanticColors.income : colors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

/// Results header: uppercase result count (left) + the signed net of
/// [expenses] in the profile currency (right), styled like a day header.
class ResultsSummaryHeader extends StatelessWidget {
  const ResultsSummaryHeader({super.key, required this.expenses, required this.currency, required this.translations});

  final List<Expense> expenses;
  final String currency;
  final Translations? translations;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final net = expenses.where((e) => e.currency == currency).fold<int>(0, (sum, e) => sum + signedCents(e));
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.smMd),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            (translations?.t('transactions.results') ?? '{{count}} results')
                .replaceAll('{{count}}', '${expenses.length}')
                .toUpperCase(),
            style: appHeaderStyle(colors),
          ),
          if (expenses.isNotEmpty)
            Text(
              formatSigned(net, currency),
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: net >= 0 ? context.semanticColors.income : colors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
        ],
      ),
    );
  }
}

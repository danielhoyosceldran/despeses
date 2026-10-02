import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/format/date.dart';
import '../../../core/i18n/display_name.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/navigation/bottom_up_route.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/charts/analytics_widgets.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/expense_row.dart';
import '../expense_entry/expense_entry_screen.dart';
import 'analytics_data_providers.dart';

/// Shared detail pieces --------------------------------------------------------

/// "1 transaction" / "N transactions", translated.
String transactionCountLabel(Translations? t, int count) {
  final key = count == 1 ? 'analytics.transactions_one' : 'analytics.transactions_other';
  return (t?.t(key) ?? (count == 1 ? '{{count}} transaction' : '{{count}} transactions'))
      .replaceAll('{{count}}', '$count');
}

/// Localized "month year" label, first letter capitalized.
String _monthTitle(DateTime month) {
  final s = DateFormat.yMMMM(dateLocale).format(month);
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Opens a transaction for editing; on save the analytics caches are dropped
/// so every section and detail reflects the change.
Future<void> openAnalyticsTransaction(BuildContext context, WidgetRef ref, String expenseId) async {
  final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
    bottomUpRoute(ExpenseEntryScreen(expenseId: expenseId)),
  );
  if (saved == true) invalidateAnalyticsSections(ref);
}

/// Big summary panel at the top of a detail: label, total, then a muted line
/// with the transaction count and the average ticket (plus savings if any).
class DetailSummaryCard extends StatelessWidget {
  const DetailSummaryCard({
    super.key,
    required this.label,
    required this.totalCents,
    required this.currency,
    required this.count,
    this.averageCents,
    this.savingsCents = 0,
    this.translations,
  });

  final String label;
  final int totalCents;
  final String currency;
  final int count;
  final int? averageCents;
  final int savingsCents;
  final Translations? translations;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final t = translations;
    final parts = [
      transactionCountLabel(t, count),
      if (averageCents != null)
        (t?.t('analytics.average_ticket') ?? 'avg {{amount}}')
            .replaceAll('{{amount}}', formatAmount(averageCents!, currency)),
    ];
    return AppCard.large(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: appHeaderStyle(colors)),
          const SizedBox(height: AppSpacing.sm),
          AmountText(amountCents: totalCents, currency: currency, style: appDisplay(colors, fontSize: 32)),
          const SizedBox(height: AppSpacing.sm),
          Text(parts.join('  ·  '), style: muted),
          if (savingsCents > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${t?.t('expenses.type_ahorro') ?? 'Savings'}: ${formatAmount(savingsCents, currency)}',
              style: muted.copyWith(color: context.semanticColors.savings),
            ),
          ],
        ],
      ),
    );
  }
}

/// Uppercase section header used between detail blocks.
class DetailSectionHeader extends StatelessWidget {
  const DetailSectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.lg, AppSpacing.xs, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(title.toUpperCase(), style: appHeaderStyle(colors))),
          if (trailing != null) Text(trailing!, style: appHeaderStyle(colors)),
        ],
      ),
    );
  }
}

/// Transactions grouped under a per-day header (newest day first). Each row
/// opens the transaction for editing.
class TransactionsByDay extends ConsumerWidget {
  const TransactionsByDay({super.key, required this.expenses, required this.translations});

  /// Already sorted newest first.
  final List<Expense> expenses;
  final Translations? translations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    if (expenses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: Text(
            translations?.t('analytics.empty_transactions') ?? 'No transactions in this period.',
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
        ),
      );
    }
    final children = <Widget>[];
    DateTime? day;
    for (final e in expenses) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      if (d != day) {
        day = d;
        children.add(Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.xs, children.isEmpty ? 0 : AppSpacing.smMd, AppSpacing.xs, AppSpacing.sm),
          child: Text(DateFormat.MMMEd(dateLocale).format(d).toUpperCase(), style: appHeaderStyle(colors)),
        ));
      }
      children.add(ExpenseRow(
        expense: e,
        translations: translations,
        onTap: () => openAnalyticsTransaction(context, ref, e.id),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// Back circle + breadcrumb path + month, shown at the top of a detail.
class DetailBreadcrumb extends StatelessWidget {
  const DetailBreadcrumb({super.key, required this.path, required this.month});

  final String path;
  final DateTime? month;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Material(
          color: colors.surfaceAlt,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Icon(LucideIcons.arrowLeft300, size: 18, color: colors.text),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.smMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(path, style: Theme.of(context).textTheme.labelLarge, overflow: TextOverflow.ellipsis),
              if (month != null)
                Text(
                  _monthTitle(month!),
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.textMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _detailScaffold({required String title, required Widget body}) => Scaffold(
      body: Column(
        children: [
          AppTopBar(title: title),
          Expanded(child: body),
        ],
      ),
    );

/// Category detail ------------------------------------------------------------

/// One category (any depth) for one month: summary, a subcategory donut +
/// breakdown when it has children with spend, and every transaction in its
/// subtree. Pushed as a real route so the OS back gesture steps back up the
/// tree; tapping a subcategory pushes another instance.
class CategoryDetailScreen extends ConsumerWidget {
  const CategoryDetailScreen({super.key, required this.month, required this.currency, required this.breadcrumb});

  final DateTime month;
  final String currency;

  /// Root → … → this category.
  final List<Category> breadcrumb;

  static void push(BuildContext context, {required DateTime month, required String currency, required List<Category> breadcrumb}) {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => CategoryDetailScreen(month: month, currency: currency, breadcrumb: breadcrumb)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).asData?.value;
    String name(Category c) => t == null ? c.name : displayNameFor(t, name: c.name, isDefault: c.isDefault);
    final category = breadcrumb.last;
    final slicesArgs = (month: month, currency: currency, parentId: category.id);
    final txArgs = (month: month, currency: currency, categoryId: category.id);
    final slicesAsync = ref.watch(categorySectionProvider(slicesArgs));
    final txAsync = ref.watch(categoryTransactionsProvider(txArgs));

    Widget body;
    if (slicesAsync.hasError || txAsync.hasError) {
      body = ErrorRetry(
        onRetry: () {
          ref.invalidate(categorySectionProvider(slicesArgs));
          ref.invalidate(categoryTransactionsProvider(txArgs));
        },
        message: t?.t('analytics.error_section') ?? 'Could not load this section.',
      );
    } else if (!slicesAsync.hasValue || !txAsync.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final data = slicesAsync.value!;
      final expenses = txAsync.value!;
      final total = expenses.fold<int>(0, (s, e) => s + e.amount);
      final sliceTotal = data.slices.fold<int>(0, (s, e) => s + e.amountCents);
      final colors = context.appColors;
      body = ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xxl),
        children: [
          DetailBreadcrumb(path: breadcrumb.map(name).join('  ›  '), month: month),
          const SizedBox(height: AppSpacing.md),
          DetailSummaryCard(
            label: t?.t('analytics.spent_label') ?? 'Spent',
            totalCents: total,
            currency: currency,
            count: expenses.length,
            averageCents: expenses.isEmpty ? null : (total / expenses.length).round(),
            translations: t,
          ),
          if (data.slices.isNotEmpty) ...[
            DetailSectionHeader(t?.t('analytics.subcategories') ?? 'Subcategories'),
            AppCard.large(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: DonutChart(
                size: 200,
                slices: [
                  for (var i = 0; i < data.slices.length; i++)
                    DonutSlice(
                      color: AppDataColors.cycle[i % AppDataColors.cycle.length],
                      value: data.slices[i].amountCents.toDouble(),
                      drillable: true,
                    ),
                ],
                center: Text(
                  '${data.slices.length}',
                  style: appDisplay(colors, fontSize: 28),
                ),
                onTap: (i) => _open(context, data.categoryById[data.slices[i].categoryId]),
              ),
            ),
            const SizedBox(height: AppSpacing.smMd),
            BreakdownCard(rows: [
              for (var i = 0; i < data.slices.length; i++)
                BreakdownRow(
                  color: AppDataColors.cycle[i % AppDataColors.cycle.length],
                  label: data.labels[data.slices[i].categoryId] ?? '',
                  amount: formatAmount(data.slices[i].amountCents, currency),
                  share: sliceTotal == 0 ? 0 : data.slices[i].amountCents / sliceTotal,
                  meta: transactionCountLabel(t, data.slices[i].count),
                  onTap: () => _open(context, data.categoryById[data.slices[i].categoryId]),
                ),
            ]),
          ],
          DetailSectionHeader(
            t?.t('analytics.transactions') ?? 'Transactions',
            trailing: '${expenses.length}',
          ),
          TransactionsByDay(expenses: expenses, translations: t),
        ],
      );
    }
    return _detailScaffold(title: name(category), body: body);
  }

  void _open(BuildContext context, Category? child) {
    if (child == null) return;
    push(context, month: month, currency: currency, breadcrumb: [...breadcrumb, child]);
  }
}

/// Tag detail -----------------------------------------------------------------

/// One tag for one month: summary (spent, savings apart), spend by category
/// and every transaction carrying the tag.
class TagDetailScreen extends ConsumerWidget {
  const TagDetailScreen({super.key, required this.month, required this.currency, required this.tagId, required this.label});

  final DateTime month;
  final String currency;
  final String tagId;
  final String label;

  static void push(BuildContext context, {required DateTime month, required String currency, required String tagId, required String label}) {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => TagDetailScreen(month: month, currency: currency, tagId: tagId, label: label)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).asData?.value;
    final args = (month: month, currency: currency, tagId: tagId);
    final body = ref.watch(tagDetailProvider(args)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorRetry(
            onRetry: () => ref.invalidate(tagDetailProvider(args)),
            message: t?.t('analytics.error_section') ?? 'Could not load this section.',
          ),
          data: (d) {
            final spendCount = d.expenses.where((e) => e.type == 'expense').length;
            final byCategoryTotal = d.byCategory.fold<int>(0, (s, e) => s + e.amountCents);
            return ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xxl),
              children: [
                DetailBreadcrumb(path: '#$label', month: month),
                const SizedBox(height: AppSpacing.md),
                DetailSummaryCard(
                  label: t?.t('analytics.spent_label') ?? 'Spent',
                  totalCents: d.spent,
                  currency: currency,
                  count: d.expenses.length,
                  averageCents: spendCount == 0 ? null : (d.spent / spendCount).round(),
                  savingsCents: d.savings,
                  translations: t,
                ),
                if (d.byCategory.isNotEmpty) ...[
                  DetailSectionHeader(t?.t('analytics.by_category') ?? 'By category'),
                  BreakdownCard(rows: [
                    for (var i = 0; i < d.byCategory.length; i++)
                      BreakdownRow(
                        color: AppDataColors.cycle[i % AppDataColors.cycle.length],
                        label: d.labels[d.byCategory[i].categoryId] ?? '',
                        amount: formatAmount(d.byCategory[i].amountCents, currency),
                        share: byCategoryTotal == 0 ? 0 : d.byCategory[i].amountCents / byCategoryTotal,
                        meta: transactionCountLabel(t, d.byCategory[i].count),
                      ),
                  ]),
                ],
                DetailSectionHeader(
                  t?.t('analytics.transactions') ?? 'Transactions',
                  trailing: '${d.expenses.length}',
                ),
                TransactionsByDay(expenses: d.expenses, translations: t),
              ],
            );
          },
        );
    return _detailScaffold(title: label, body: body);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../../core/i18n/display_name.dart';
import '../../core/i18n/translations.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database.dart';
import '../../domain/repositories/analytics/analytics_math.dart';

/// Transaction row as a hairline card: uppercase category line, title, and the
/// signed amount in the display face (income emerald / expense rose / refund
/// neutral).
class ExpenseRow extends ConsumerWidget {
  const ExpenseRow({
    super.key,
    required this.expense,
    required this.translations,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  final Expense expense;
  final Translations? translations;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final sign = switch (expense.type) {
      'income' => '+',
      'refund' => '±',
      _ => '-',
    };
    final color = context.amountColorForType(expense.type);
    final title = expense.description?.isNotEmpty == true ? expense.description! : expense.type;
    final categoryLabel = _categoryLabel(ref);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: selected ? colors.mutedFill(0.5) : colors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.smMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimens.radiusCard),
              border: Border.all(color: colors.borderSoft, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (selectionMode) ...[
                  Checkbox(value: selected, onChanged: (_) => onTap()),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (categoryLabel != null && categoryLabel.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            categoryLabel.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      if (isScheduled(expense))
                        Text(
                          translations?.t('expenses.scheduled') ?? 'Scheduled',
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.textMuted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '$sign${formatMoney(expense.amount, expense.currency)}',
                  style: appDisplay(colors, fontSize: 18, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _categoryLabel(WidgetRef ref) {
    if (expense.categoryId == null || translations == null) return null;
    final categories = ref.watch(categoriesListProvider).valueOrNull;
    if (categories == null) return null;
    final match = categories.where((c) => c.id == expense.categoryId);
    if (match.isEmpty) return null;
    return displayNameFor(translations!, name: match.first.name, isDefault: match.first.isDefault);
  }
}

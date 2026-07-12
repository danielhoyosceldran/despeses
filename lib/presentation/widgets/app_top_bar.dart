import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';

/// Shared top header (mock: `px-6` row, `justify-between`). Left side is either
/// a month pager (chevrons + uppercase label) or a display title; the right
/// side is a settings gear that jumps to the Settings tab. Extra [actions] sit
/// just before the gear. In selection mode it swaps to a count + clear/delete
/// row.
///
/// Style-only replacement for the old `MonthHeaderBar` — no Material `AppBar`
/// on the tab screens anymore; this lives inside the body.
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    this.month,
    this.onChangeMonth,
    this.title,
    this.actions = const [],
    this.selectionCount = 0,
    this.onClearSelection,
    this.onDeleteSelection,
    this.showSettings = true,
  });

  /// When set (with [onChangeMonth]), the left side shows the month pager.
  final DateTime? month;
  final void Function(int delta)? onChangeMonth;

  /// When set (and no [month]), the left side shows this display title.
  final String? title;

  /// Extra trailing actions rendered before the settings gear.
  final List<Widget> actions;

  /// > 0 puts the bar in multi-select mode (count + clear + delete).
  final int selectionCount;
  final VoidCallback? onClearSelection;
  final VoidCallback? onDeleteSelection;

  final bool showSettings;

  bool get _selection => selectionCount > 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
        child: SizedBox(
          height: 44,
          child: _selection ? _buildSelection(context, colors) : _buildDefault(context, colors),
        ),
      ),
    );
  }

  Widget _buildDefault(BuildContext context, AppColors colors) {
    return Row(
      children: [
        Expanded(child: _leftContent(context, colors)),
        for (final action in actions) ...[
          action,
          const SizedBox(width: AppSpacing.xs),
        ],
        if (showSettings)
          TopBarCircleButton(
            icon: LucideIcons.settings300,
            filled: true,
            onTap: () => context.push('/account'),
          ),
      ],
    );
  }

  Widget _leftContent(BuildContext context, AppColors colors) {
    if (month != null && onChangeMonth != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TopBarCircleButton(icon: LucideIcons.chevronLeft300, onTap: () => onChangeMonth!(-1)),
          Text(
            toBeginningOfSentenceCase(DateFormat.yMMMM().format(month!)).toUpperCase(),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
              color: colors.textMuted,
            ),
          ),
          TopBarCircleButton(icon: LucideIcons.chevronRight300, onTap: () => onChangeMonth!(1)),
        ],
      );
    }
    if (title != null) {
      return Text(
        title!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineSmall,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSelection(BuildContext context, AppColors colors) {
    return Row(
      children: [
        TopBarCircleButton(icon: LucideIcons.x300, onTap: onClearSelection ?? () {}),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '$selectionCount selected',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TopBarCircleButton(icon: LucideIcons.trash2300, onTap: onDeleteSelection ?? () {}),
      ],
    );
  }
}

/// Circular icon button. Ghost by default (muted, transparent), or a filled
/// muted chip when [filled] — the mock's persistent header action.
class TopBarCircleButton extends StatelessWidget {
  const TopBarCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  /// Overrides the icon tint (e.g. accent when a filter is active).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final iconColor = color ?? (filled ? colors.text : colors.textMuted);
    return Material(
      color: filled ? colors.surfaceAlt : Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }
}

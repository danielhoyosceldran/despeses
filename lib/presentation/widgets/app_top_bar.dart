import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/haptics/haptics.dart';
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
    this.pageController,
    this.monthForPage,
    this.fallbackPage = 0,
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

  /// When [pageController] and [monthForPage] are both set, the month label
  /// tracks the swipe continuously (sliding + revealing the incoming month)
  /// instead of only flipping on page settle. [fallbackPage] is the page shown
  /// before the controller is attached (its `initialPage`).
  final PageController? pageController;
  final DateTime Function(int page)? monthForPage;
  final int fallbackPage;

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
        if (showSettings) const _SettingsGearButton(),
      ],
    );
  }

  Widget _leftContent(BuildContext context, AppColors colors) {
    if (month != null && onChangeMonth != null) {
      final labelStyle = TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: colors.textMuted,
      );
      final tracking = pageController != null && monthForPage != null;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TopBarCircleButton(icon: LucideIcons.chevronLeft300, onTap: () => onChangeMonth!(-1)),
          SizedBox(
            width: 168,
            height: 20,
            child: tracking
                ? _SlidingMonthLabel(
                    controller: pageController!,
                    monthForPage: monthForPage!,
                    fallbackPage: fallbackPage,
                    style: labelStyle,
                  )
                : Center(
                    child: Text(
                      toBeginningOfSentenceCase(DateFormat.yMMMM().format(month!)).toUpperCase(),
                      style: labelStyle,
                    ),
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

/// Month label that tracks a [PageController] continuously: as the page swipes,
/// the current month slides out and the incoming month slides in and fades up,
/// 1:1 with the finger — a filmstrip driven by the fractional page value. Only
/// the label within one slot-width of centre is visible.
class _SlidingMonthLabel extends StatelessWidget {
  const _SlidingMonthLabel({
    required this.controller,
    required this.monthForPage,
    required this.fallbackPage,
    required this.style,
  });

  final PageController controller;
  final DateTime Function(int page) monthForPage;
  final int fallbackPage;
  final TextStyle style;

  String _label(int page) =>
      toBeginningOfSentenceCase(DateFormat.yMMMM().format(monthForPage(page))).toUpperCase();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            var page = fallbackPage.toDouble();
            if (controller.hasClients && controller.position.haveDimensions) {
              page = controller.page ?? page;
            }
            final current = page.round();
            return ClipRect(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (var i = current - 1; i <= current + 1; i++)
                    Transform.translate(
                      offset: Offset((i - page) * w, 0),
                      child: Opacity(
                        opacity: (1 - (i - page).abs()).clamp(0.0, 1.0),
                        child: Text(
                          _label(i),
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: style,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Header settings gear: tap opens `/account` (top-down slide, see
/// `topDownPage`); a downward drag past the threshold (or a downward fling)
/// opens it too, mirroring the add-transaction/budget FABs' drag-open gesture.
class _SettingsGearButton extends ConsumerStatefulWidget {
  const _SettingsGearButton();

  @override
  ConsumerState<_SettingsGearButton> createState() => _SettingsGearButtonState();
}

class _SettingsGearButtonState extends ConsumerState<_SettingsGearButton> {
  static const double _kThresholdPx = 48;
  static const double _kFlingVelocity = 600;

  double _dragPx = 0;
  bool _armed = false;
  bool _opened = false;

  void _open() {
    if (_opened) return;
    _opened = true;
    context.push('/account');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (_) {
        _opened = false;
        ref.read(hapticsProvider).medium();
      },
      onVerticalDragUpdate: (d) {
        setState(() {
          _dragPx = (_dragPx + d.delta.dy).clamp(0.0, 64.0);
          _armed = _dragPx >= _kThresholdPx;
        });
        if (_armed) _open();
      },
      onVerticalDragEnd: (d) {
        if (!_opened && (d.primaryVelocity ?? 0) >= _kFlingVelocity) _open();
        setState(() {
          _dragPx = 0;
          _armed = false;
        });
      },
      onVerticalDragCancel: () => setState(() {
        _dragPx = 0;
        _armed = false;
      }),
      child: Transform.translate(
        offset: Offset(0, _dragPx * 0.3),
        child: TopBarCircleButton(
          icon: LucideIcons.settings300,
          filled: true,
          onTap: _open,
        ),
      ),
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

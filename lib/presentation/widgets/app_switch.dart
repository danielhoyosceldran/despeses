import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics/haptics.dart';
import '../../core/theme/app_theme.dart';

/// App-styled toggle replacing Material [Switch]. Pill track fills with [accent]
/// when on / [surfaceAlt] when off, thumb slides across with a soft shadow.
/// Animates on the shared [AppDimens.animFast]/[AppDimens.animCurve] tokens and
/// routes its tick through [HapticsService].
class AppSwitch extends ConsumerWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const double _width = 46;
  static const double _height = 28;
  static const double _thumb = 22;
  static const double _pad = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final enabled = onChanged != null;

    void toggle() {
      if (!enabled) return;
      ref.read(hapticsProvider).selection();
      onChanged!(!value);
    }

    // On-track uses a softened accent (opposite-theme ink at reduced opacity)
    // so the toggle reads as active without the full high-contrast fill.
    final trackColor =
        value ? colors.accent.withValues(alpha: 0.55) : colors.mutedFill(0.5);
    final thumbColor = value ? colors.onAccent : colors.surface;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: toggle,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDimens.animFast,
          curve: AppDimens.animCurve,
          width: _width,
          height: _height,
          padding: const EdgeInsets.all(_pad),
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
          child: AnimatedAlign(
            duration: AppDimens.animFast,
            curve: AppDimens.animCurve,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: _thumb,
              height: _thumb,
              decoration: BoxDecoration(
                color: thumbColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                    color: colors.shadow,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Scales its child down on press and back on release (`active:scale-95` in the
/// mock). Wrap the FAB or any tappable that should feel springy.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.95,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: AppDimens.animCurve,
        child: widget.child,
      ),
    );
  }
}

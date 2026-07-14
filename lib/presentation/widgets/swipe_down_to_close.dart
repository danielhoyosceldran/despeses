import 'package:flutter/material.dart';

/// Wraps a scrollable [child] so that a downward swipe **while the scroll view
/// is already at the top** (i.e. it can't scroll up any further) closes the
/// screen via [onClose].
///
/// This is a plain trigger, **not** an interactive animation that follows the
/// finger: once the accumulated overscroll while dragging passes
/// [thresholdPx], [onClose] fires once and the gesture is consumed.
class SwipeDownToClose extends StatefulWidget {
  const SwipeDownToClose({
    super.key,
    required this.onClose,
    required this.child,
    this.thresholdPx = 96,
  });

  /// Called once when a qualifying pull-down gesture completes.
  final VoidCallback onClose;

  /// Downward overscroll (px) that must accumulate during a single drag before
  /// the close is triggered.
  final double thresholdPx;

  final Widget child;

  @override
  State<SwipeDownToClose> createState() => _SwipeDownToCloseState();
}

class _SwipeDownToCloseState extends State<SwipeDownToClose> {
  /// Accumulated downward overscroll for the current drag (px, >= 0).
  double _pull = 0;
  bool _fired = false;

  bool _onNotification(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      _pull = 0;
      _fired = false;
    } else if (n is OverscrollNotification) {
      // overscroll < 0 → dragging content down past the top edge. Only count
      // user drags (dragDetails != null), not ballistic/settle overscroll.
      if (!_fired && n.dragDetails != null && n.overscroll < 0) {
        _pull += -n.overscroll;
        if (_pull >= widget.thresholdPx) {
          _fired = true;
          widget.onClose();
        }
      }
    } else if (n is ScrollEndNotification) {
      _pull = 0;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: widget.child,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics/haptics.dart';

/// Builds the sheet page, given a [close] callback that dismisses it with a
/// result (mirrors `Navigator.pop`). Wire it into the entry screen's `onClose`.
typedef SheetPageBuilder = Widget Function(
    BuildContext context, void Function(Object? result) close);

/// A floating "add" button that is the **motor** of the entry screen's opening
/// animation:
/// - **tap** — opens the sheet with the normal open animation, and
/// - **drag up** — the **button follows the finger 1:1** the whole drag. A haptic
///   fires the instant the drag starts (the button "unsticks"), and the entry
///   screen rises tracking finger travel from the very first pixel. A threshold
///   acts only as the release trigger: release past it (or fling up) completes
///   the open; release below cancels and everything settles back down (no haptic
///   at the threshold).
///
/// The sheet is shown in an [OverlayEntry] driven by a controller here — **not**
/// a pushed route. Pushing a route mid-drag cancels the active drag gesture
/// (the recognizer is torn down when the navigator restacks), which is why this
/// uses an overlay instead. The hosted page closes via the `close` callback
/// (wired to the entry screen's `onClose`), so it never needs `Navigator.pop`.
///
/// [onResult] receives the value the page closes with (e.g. `true` on save).
class DragUpAction extends ConsumerStatefulWidget {
  const DragUpAction({
    super.key,
    required this.pageBuilder,
    required this.builder,
    this.onResult,
  });

  final SheetPageBuilder pageBuilder;
  final Widget Function(BuildContext context, bool armed, VoidCallback onTap)
      builder;
  final ValueChanged<Object?>? onResult;

  @override
  ConsumerState<DragUpAction> createState() => _DragUpActionState();
}

class _DragUpActionState extends ConsumerState<DragUpAction>
    with SingleTickerProviderStateMixin {
  /// Finger travel (px, upward) past which release opens the sheet. Only a
  /// release trigger — the sheet already tracks the finger from the first pixel.
  static const double _kThresholdPx = 72;

  /// Upward fling velocity (px/s) that opens regardless of distance.
  static const double _kFlingVelocity = 700;

  /// Button settle-home duration after release.
  static const Duration _kSettle = Duration(milliseconds: 220);
  static const Duration _kOpen = Duration(milliseconds: 300);

  late final AnimationController _sheet =
      AnimationController(vsync: this, duration: _kOpen);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(_sheet);

  OverlayEntry? _entry;
  bool _closing = false;

  double _height = 0;
  bool _dragging = false;
  bool _armed = false;

  /// Upward finger travel from the drag start, in px (>= 0).
  double _dragPx = 0;

  @override
  void dispose() {
    _entry?.remove();
    _sheet.dispose();
    super.dispose();
  }

  // --- sheet lifecycle -------------------------------------------------------

  void _present() {
    _closing = false;
    _sheet.value = 0;
    final entry = OverlayEntry(
      builder: (context) {
        final sheet = SlideTransition(
          position: _slide,
          child: widget.pageBuilder(context, _dismiss),
        );
        // Intercept Android system back to close the sheet (not the tab below).
        // Requires a Router ancestor (go_router provides one); skip otherwise.
        if (Router.maybeOf(context) == null) return sheet;
        return BackButtonListener(
          onBackButtonPressed: () async {
            _dismiss(null);
            return true;
          },
          child: sheet,
        );
      },
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  /// Close the sheet: slide down, then remove and report [result].
  void _dismiss(Object? result) {
    if (_closing || _entry == null) return;
    _closing = true;
    _sheet
        .animateTo(0, duration: _kSettle, curve: Curves.easeInCubic)
        .whenComplete(() {
      _entry?.remove();
      _entry = null;
      widget.onResult?.call(result);
    });
  }

  // --- interactions ----------------------------------------------------------

  void _onTap() {
    _present();
    _sheet.animateTo(1, duration: _kOpen, curve: Curves.easeOutCubic);
  }

  void _start() {
    _height = MediaQuery.sizeOf(context).height;
    _present();
    // Haptic the instant the drag begins — the button "unsticks".
    ref.read(hapticsProvider).medium();
    setState(() {
      _dragging = true;
      _armed = false;
      _dragPx = 0;
    });
  }

  void _update(double dy) {
    if (!_dragging || _height == 0) return;
    // Button follows the finger 1:1 (dy < 0 is upward).
    _dragPx = (_dragPx - dy).clamp(0.0, _height);
    // Armed = past threshold; only decides open-on-release (no haptic here).
    _armed = _dragPx >= _kThresholdPx;
    // Sheet tracks finger travel from the first pixel.
    _sheet.value = (_dragPx / _height).clamp(0.0, 1.0);
    setState(() {});
  }

  void _end(double velocity) {
    final open = _armed || velocity <= -_kFlingVelocity;
    setState(() {
      _dragging = false;
      _dragPx = 0;
    });
    if (open) {
      _sheet.animateTo(1, duration: _kOpen, curve: Curves.easeOutCubic);
    } else {
      _dismiss(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tap is left to the child button (keeps ripple/enabled state); this
    // detector only claims vertical drags, which win the arena once the finger
    // moves past slop.
    return GestureDetector(
      onVerticalDragStart: (_) => _start(),
      onVerticalDragUpdate: (d) => _update(d.delta.dy),
      onVerticalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
      onVerticalDragCancel: () => _end(0),
      // The button chases the finger while dragging (0ms) and eases home on
      // release (_kSettle).
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _dragging ? _dragPx : 0),
        duration: _dragging ? Duration.zero : _kSettle,
        curve: Curves.easeOut,
        builder: (context, offset, child) => Transform.translate(
          offset: Offset(0, -offset),
          child: child,
        ),
        child: widget.builder(context, _armed, _onTap),
      ),
    );
  }
}

/// A Material [FloatingActionButton] wired to [DragUpAction] (tap or drag-up to
/// open [pageBuilder]).
class DragUpFab extends StatelessWidget {
  const DragUpFab({
    super.key,
    required this.pageBuilder,
    required this.child,
    this.onResult,
  });

  final SheetPageBuilder pageBuilder;
  final Widget child;
  final ValueChanged<Object?>? onResult;

  @override
  Widget build(BuildContext context) {
    return DragUpAction(
      pageBuilder: pageBuilder,
      onResult: onResult,
      builder: (context, armed, onTap) => FloatingActionButton(
        onPressed: onTap,
        elevation: armed ? 12 : null,
        // No hero: several tab FABs stay mounted at once (StatefulShell), so a
        // shared default hero tag collides. We animate the sheet ourselves.
        heroTag: null,
        child: child,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/i18n/translations.dart';
import 'confirm_dialog.dart';

/// Routes every way of leaving an entry screen — besides its own close
/// controls, which call [onRequestClose] directly — through [onRequestClose],
/// so the screen can ask before discarding unsaved changes:
///
/// - pushed as a route: system back is blocked by a [PopScope] and forwarded.
///   (`Navigator.pop` after a save is not affected by [PopScope].)
/// - hosted as a `DragUpFab` overlay ([overlayMode]): system back is caught by
///   a [BackButtonListener] that takes priority over the host's own one.
class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.overlayMode,
    required this.onRequestClose,
    required this.child,
  });

  final bool overlayMode;
  final VoidCallback onRequestClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget result = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onRequestClose();
      },
      child: child,
    );
    // BackButtonListener needs a Router ancestor (go_router provides one).
    if (overlayMode && Router.maybeOf(context) != null) {
      result = BackButtonListener(
        onBackButtonPressed: () async {
          onRequestClose();
          return true;
        },
        child: result,
      );
    }
    return result;
  }
}

/// "Discard changes?" confirmation. Returns true when the user chose to
/// discard.
Future<bool> confirmDiscardChanges(BuildContext context, Translations? t) {
  return showConfirmDialog(
    context,
    title: t?.t('common.discard_title') ?? 'Discard changes?',
    message: t?.t('common.discard_message') ?? 'Your unsaved changes will be lost.',
    confirmLabel: t?.t('common.discard') ?? 'Discard',
    cancelLabel: t?.t('common.cancel') ?? 'Cancel',
    destructive: true,
  );
}

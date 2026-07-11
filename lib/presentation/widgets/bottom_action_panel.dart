import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Panel inferior animado embebido en la pantalla del formulario (no
/// [showModalBottomSheet]). Anima su altura entre 0 y el alto del contenido,
/// hasta un máximo, con fade del contenido.
class BottomActionPanel extends StatelessWidget {
  const BottomActionPanel({
    super.key,
    required this.isOpen,
    required this.child,
    this.maxHeight = 340,
  });

  final bool isOpen;
  final Widget? child;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AnimatedContainer(
      duration: AppDimens.animFast,
      curve: AppDimens.animCurve,
      constraints: BoxConstraints(maxHeight: isOpen ? maxHeight : 0),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDimens.radiusSheet)),
        border: Border(top: BorderSide(color: colors.border, width: 1)),
        boxShadow: isOpen ? AppShadows.sheet(colors) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedOpacity(
        duration: AppDimens.animFast,
        opacity: isOpen ? 1 : 0,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

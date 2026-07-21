import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Horizontal push transition for settings/account sub-screens (categories,
/// tags, profile, export, ...): slides in from the right on push, and the
/// reverse (slide out to the right) on pop. Use as a `GoRoute.pageBuilder`.
CustomTransitionPage<T> slideFromRightPage<T>({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

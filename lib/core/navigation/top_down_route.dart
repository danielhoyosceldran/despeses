import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Vertical push transition for the Account/Settings hub (opened via the
/// header gear): slides in from the top on push, and the reverse (slide out
/// upward) on pop. Mirrors `bottomUpRoute` but from the opposite edge. Use as
/// the `GoRoute.pageBuilder` for `/account`.
CustomTransitionPage<T> topDownPage<T>({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

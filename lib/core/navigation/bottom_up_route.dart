import 'package:flutter/material.dart';

/// A modal route that slides its [page] up from the bottom on push and back
/// down on pop — used for the "add / edit" entry screens opened from the FABs.
///
/// The reverse transition mirrors the forward one, so dismissing (down-chevron
/// or system back) animates the screen downward off-screen.
Route<T> bottomUpRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

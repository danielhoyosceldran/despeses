import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Centered "nothing here" placeholder (C9) — one widget for the empty states
/// that were re-implemented per screen (analytics sections, lists).
class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}

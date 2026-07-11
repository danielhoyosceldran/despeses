import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Big bold screen title rendered in the body (Revolut-style), used where the
/// app bar is intentionally left title-less. Optional trailing [action].
class PageTitleHeader extends StatelessWidget {
  const PageTitleHeader(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
          ),
          ?action,
        ],
      ),
    );
  }
}

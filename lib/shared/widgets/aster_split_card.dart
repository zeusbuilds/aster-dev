import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'aster_divider.dart';
import 'squircle.dart';

/// One outlined squircle containing a form and its contextual action strip.
/// A single outer shape prevents double strokes and mismatched corner joins.
class AsterSplitCard extends StatelessWidget {
  const AsterSplitCard({
    super.key,
    required this.content,
    required this.footer,
    this.tonalFooter = true,
  });

  final Widget content;
  final Widget footer;
  final bool tonalFooter;

  @override
  Widget build(BuildContext context) {
    return Squircle(
      color: context.colorScheme.surface,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.xl,
              vertical: context.spacing.lg,
            ),
            child: content,
          ),
          const AsterDivider(),
          ColoredBox(
            color: tonalFooter
                ? context.appColors.surfaceSubtle
                : context.colorScheme.surface,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.spacing.xl,
                vertical: context.spacing.sm,
              ),
              child: footer,
            ),
          ),
        ],
      ),
    );
  }
}

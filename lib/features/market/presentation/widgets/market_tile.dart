import 'package:flutter/material.dart';

import 'package:aster/shared/shared.dart';

/// Market tile widget displaying a squircle with icon and label
///
/// Icon is inside the squircle, label is below it
class MarketTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const MarketTile({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radius = context.radius;
    final textTheme = context.textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Squircle(
                color: Colors.transparent,
                borderColor: colors.border2,
                borderRadius: radius.radius24,
                padding: EdgeInsets.all(spacing.spacing20),
                child: Icon(icon, size: spacing.spacing32, color: colors.text1),
              ),
            ),
          ),
          SizedBox(height: spacing.spacing8),
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.text1,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

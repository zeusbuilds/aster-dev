import 'package:flutter/material.dart';

import 'package:aster/shared/shared.dart';

/// Individual control button for scan frame
class ScanControlButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const ScanControlButton({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: spacing.spacing26,
        height: spacing.spacing26,
        decoration: BoxDecoration(shape: BoxShape.circle, color: colors.fill6),
        child: Center(child: child),
      ),
    );
  }
}

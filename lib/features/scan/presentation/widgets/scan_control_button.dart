import 'package:flutter/material.dart';

import 'package:aster/shared/shared.dart';

/// Individual control button for scan frame
class ScanControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const ScanControlButton({super.key, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(spacing.spacing8),
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black),
        child: Icon(icon, color: colors.text5, size: spacing.spacing16),
      ),
    );
  }
}

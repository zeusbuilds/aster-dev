import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Individual control button for scan frame
class ScanControlButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const ScanControlButton({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: spacing.xxl,
        height: spacing.xxl,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AsterColors.black,
        ),
        child: Center(child: child),
      ),
    );
  }
}

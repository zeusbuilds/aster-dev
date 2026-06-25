import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Individual control button for scan frame
class ScanControlButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String semanticLabel;

  const ScanControlButton({
    super.key,
    required this.child,
    required this.semanticLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final icons = context.icons;
    final metrics = context.metrics;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: metrics.minTouchTarget,
          height: metrics.minTouchTarget,
          child: Center(
            child: Container(
              width: icons.md,
              height: icons.md,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.scanControlSurface,
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

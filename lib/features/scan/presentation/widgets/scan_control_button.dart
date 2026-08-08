import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Individual control button for scan frame
class ScanControlButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String semanticLabel;
  final HapticIntent hapticIntent;

  const ScanControlButton({
    super.key,
    required this.child,
    required this.semanticLabel,
    this.onTap,
    this.hapticIntent = HapticIntent.lightImpact,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final icons = context.icons;
    final metrics = context.metrics;

    void activate() {
      unawaited(context.haptics.trigger(hapticIntent));
      onTap?.call();
    }

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: colors.transparentSurface,
        child: InkResponse(
          onTap: onTap == null ? null : activate,
          containedInkWell: true,
          highlightShape: BoxShape.circle,
          radius: metrics.minTouchTarget / 2,
          child: SizedBox(
            width: metrics.minTouchTarget,
            height: metrics.minTouchTarget,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.scanControlSurface,
                ),
                child: SizedBox(
                  width: icons.md,
                  height: icons.md,
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

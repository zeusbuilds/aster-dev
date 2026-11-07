import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Accessible circular command used within the Scan frame control pill.
class ScanControlButton extends StatelessWidget {
  const ScanControlButton({
    super.key,
    required this.child,
    required this.semanticLabel,
    this.onTap,
    this.selected,
    this.value,
    this.busy = false,
    this.contentDiameter = 32,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool? selected;
  final String? value;

  /// Silently guards a command without replacing or dimming its content.
  final bool busy;

  /// Shared visible diameter for all commands in the control pill.
  final double contentDiameter;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.metrics;
    final stateLayers = context.stateLayers;
    final diameter = contentDiameter;
    // Keep 48 px tap targets around compact circles. Larger accessibility
    // circles retain at least 4 px per side so adjacent controls never touch.
    final touchExtent = math.max(
      metrics.minTouchTarget,
      diameter + context.spacing.sm,
    );

    void activate() => onTap?.call();

    final enabled = onTap != null && !busy;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: semanticLabel,
      value: value,
      onTap: enabled ? activate : null,
      excludeSemantics: true,
      child: Material(
        color: colors.transparentSurface,
        child: InkResponse(
          onTap: enabled ? activate : null,
          containedInkWell: true,
          highlightShape: BoxShape.circle,
          radius: touchExtent / 2,
          child: Opacity(
            opacity: enabled || busy
                ? stateLayers.visible
                : stateLayers.disabled,
            child: SizedBox(
              width: touchExtent,
              height: touchExtent,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.scanControlSurface,
                  ),
                  child: SizedBox(
                    width: diameter,
                    height: diameter,
                    child: Center(child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

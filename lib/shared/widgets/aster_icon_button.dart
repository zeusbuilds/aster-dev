import 'dart:async';

import 'package:flutter/material.dart';

import '../feedback/feedback.dart';
import '../theme/theme.dart';

/// Accessible icon command with a required tooltip and semantic haptic intent.
class AsterIconButton extends StatelessWidget {
  const AsterIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
    this.iconSize,
    this.hapticIntent = HapticIntent.lightImpact,
    this.showTooltip = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double? iconSize;
  final HapticIntent hapticIntent;
  final bool showTooltip;

  @override
  Widget build(BuildContext context) {
    void activate() {
      unawaited(context.haptics.trigger(hapticIntent));
      onPressed?.call();
    }

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      excludeSemantics: true,
      child: IconButton(
        onPressed: onPressed == null ? null : activate,
        tooltip: showTooltip ? tooltip : null,
        constraints: BoxConstraints.tightFor(
          width: context.metrics.minTouchTarget,
          height: context.metrics.minTouchTarget,
        ),
        icon: Icon(
          icon,
          size: iconSize ?? context.icons.sm,
          color: color ?? context.colorScheme.onSurface,
        ),
      ),
    );
  }
}

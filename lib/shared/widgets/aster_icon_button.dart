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
    this.alignment = Alignment.center,
    this.hapticIntent = HapticIntent.lightImpact,
    this.loading = false,
    this.showTooltip = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double? iconSize;

  /// Positions the glyph inside the stable touch target.
  ///
  /// Edge-anchored navigation controls use an inward alignment so their glyphs
  /// follow the page content edge without shrinking or shifting the tap area.
  final AlignmentGeometry alignment;

  /// Set to `null` when feedback belongs to a confirmed async result.
  final HapticIntent? hapticIntent;
  final bool loading;
  final bool showTooltip;

  @override
  Widget build(BuildContext context) {
    void activate() {
      final intent = hapticIntent;
      if (intent != null) unawaited(context.haptics.trigger(intent));
      onPressed?.call();
    }

    final enabled = onPressed != null && !loading;

    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      value: loading ? 'Loading' : null,
      liveRegion: loading,
      onTap: enabled ? activate : null,
      excludeSemantics: true,
      child: IconButton(
        onPressed: enabled ? activate : null,
        tooltip: showTooltip ? tooltip : null,
        alignment: alignment,
        constraints: BoxConstraints.tightFor(
          width: context.metrics.minTouchTarget,
          height: context.metrics.minTouchTarget,
        ),
        icon: loading
            ? SizedBox.square(
                dimension: iconSize ?? context.icons.sm,
                child: CircularProgressIndicator(
                  strokeWidth: context.strokes.progressIndicator,
                ),
              )
            : Icon(
                icon,
                size: iconSize ?? context.icons.sm,
                color: color ?? context.colorScheme.onSurface,
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Interaction/state-layer alpha values.
///
/// These are semantic decisions, not an opacity ramp. Add a value only when a
/// reusable state treatment exists in the product language.
@immutable
class AsterStateLayers extends ThemeExtension<AsterStateLayers> {
  const AsterStateLayers({
    this.visible = 1,
    this.hidden = 0,
    this.disabled = 0.5,
    this.translucentSurface = 0.8,
    this.hoverOverlay = 0.08,
    this.focusOverlay = 0.12,
  });

  final double visible;
  final double hidden;
  final double disabled;
  final double translucentSurface;
  final double hoverOverlay;
  final double focusOverlay;

  /// Focus/hover remain visible; pointer presses never paint an ink overlay.
  /// AppTheme also disables the splash factory, since these are separate
  /// Material mechanisms. Custom controls use the same policy.
  WidgetStateColor interactionOverlay(Color foreground) =>
      WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return foreground.withValues(alpha: hidden);
        }
        if (states.contains(WidgetState.focused)) {
          return foreground.withValues(alpha: focusOverlay);
        }
        if (states.contains(WidgetState.hovered)) {
          return foreground.withValues(alpha: hoverOverlay);
        }
        return foreground.withValues(alpha: hidden);
      });

  @override
  AsterStateLayers copyWith({
    double? visible,
    double? hidden,
    double? disabled,
    double? translucentSurface,
    double? hoverOverlay,
    double? focusOverlay,
  }) {
    return AsterStateLayers(
      visible: visible ?? this.visible,
      hidden: hidden ?? this.hidden,
      disabled: disabled ?? this.disabled,
      translucentSurface: translucentSurface ?? this.translucentSurface,
      hoverOverlay: hoverOverlay ?? this.hoverOverlay,
      focusOverlay: focusOverlay ?? this.focusOverlay,
    );
  }

  @override
  AsterStateLayers lerp(ThemeExtension<AsterStateLayers>? other, double t) {
    if (other is! AsterStateLayers) return this;
    return AsterStateLayers(
      visible: _lerp(visible, other.visible, t),
      hidden: _lerp(hidden, other.hidden, t),
      disabled: _lerp(disabled, other.disabled, t),
      translucentSurface: _lerp(
        translucentSurface,
        other.translucentSurface,
        t,
      ),
      hoverOverlay: _lerp(hoverOverlay, other.hoverOverlay, t),
      focusOverlay: _lerp(focusOverlay, other.focusOverlay, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

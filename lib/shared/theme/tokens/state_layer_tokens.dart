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
    this.primaryOverlay = 0.12,
    this.hoverOverlay = 0.08,
    this.focusOverlay = 0.12,
    this.pressedOverlay = 0.12,
  });

  final double visible;
  final double hidden;
  final double disabled;
  final double translucentSurface;
  final double primaryOverlay;
  final double hoverOverlay;
  final double focusOverlay;
  final double pressedOverlay;

  @override
  AsterStateLayers copyWith({
    double? visible,
    double? hidden,
    double? disabled,
    double? translucentSurface,
    double? primaryOverlay,
    double? hoverOverlay,
    double? focusOverlay,
    double? pressedOverlay,
  }) {
    return AsterStateLayers(
      visible: visible ?? this.visible,
      hidden: hidden ?? this.hidden,
      disabled: disabled ?? this.disabled,
      translucentSurface: translucentSurface ?? this.translucentSurface,
      primaryOverlay: primaryOverlay ?? this.primaryOverlay,
      hoverOverlay: hoverOverlay ?? this.hoverOverlay,
      focusOverlay: focusOverlay ?? this.focusOverlay,
      pressedOverlay: pressedOverlay ?? this.pressedOverlay,
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
      primaryOverlay: _lerp(primaryOverlay, other.primaryOverlay, t),
      hoverOverlay: _lerp(hoverOverlay, other.hoverOverlay, t),
      focusOverlay: _lerp(focusOverlay, other.focusOverlay, t),
      pressedOverlay: _lerp(pressedOverlay, other.pressedOverlay, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

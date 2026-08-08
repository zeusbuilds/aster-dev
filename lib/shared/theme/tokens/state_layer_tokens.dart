import 'package:flutter/material.dart';

/// Interaction/state-layer alpha values.
///
/// These are semantic decisions, not an opacity ramp. Add a value only when a
/// reusable state treatment exists in the product language.
@immutable
class AsterStateLayers extends ThemeExtension<AsterStateLayers> {
  const AsterStateLayers({
    this.disabled = 0.5,
    this.translucentSurface = 0.8,
    this.selectedContainer = 0.5,
    this.primaryOverlay = 0.12,
    this.hoverOverlay = 0.08,
    this.focusOverlay = 0.12,
    this.pressedOverlay = 0.12,
  });

  final double disabled;
  final double translucentSurface;
  final double selectedContainer;
  final double primaryOverlay;
  final double hoverOverlay;
  final double focusOverlay;
  final double pressedOverlay;

  @override
  AsterStateLayers copyWith({
    double? disabled,
    double? translucentSurface,
    double? selectedContainer,
    double? primaryOverlay,
    double? hoverOverlay,
    double? focusOverlay,
    double? pressedOverlay,
  }) {
    return AsterStateLayers(
      disabled: disabled ?? this.disabled,
      translucentSurface: translucentSurface ?? this.translucentSurface,
      selectedContainer: selectedContainer ?? this.selectedContainer,
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
      disabled: _lerp(disabled, other.disabled, t),
      translucentSurface: _lerp(
        translucentSurface,
        other.translucentSurface,
        t,
      ),
      selectedContainer: _lerp(selectedContainer, other.selectedContainer, t),
      primaryOverlay: _lerp(primaryOverlay, other.primaryOverlay, t),
      hoverOverlay: _lerp(hoverOverlay, other.hoverOverlay, t),
      focusOverlay: _lerp(focusOverlay, other.focusOverlay, t),
      pressedOverlay: _lerp(pressedOverlay, other.pressedOverlay, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

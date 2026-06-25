import 'package:flutter/material.dart';

/// Stroke widths for borders, dividers, focus rings, and hairline art.
@immutable
class AsterStrokes extends ThemeExtension<AsterStrokes> {
  const AsterStrokes({
    this.hairline = 0.5,
    this.divider = 1,
    this.border = 1,
    this.focusBorder = 1.5,
    this.focusRing = 3,
  });

  final double hairline;
  final double divider;
  final double border;
  final double focusBorder;
  final double focusRing;

  @override
  AsterStrokes copyWith({
    double? hairline,
    double? divider,
    double? border,
    double? focusBorder,
    double? focusRing,
  }) {
    return AsterStrokes(
      hairline: hairline ?? this.hairline,
      divider: divider ?? this.divider,
      border: border ?? this.border,
      focusBorder: focusBorder ?? this.focusBorder,
      focusRing: focusRing ?? this.focusRing,
    );
  }

  @override
  AsterStrokes lerp(ThemeExtension<AsterStrokes>? other, double t) {
    if (other is! AsterStrokes) return this;
    return AsterStrokes(
      hairline: _lerp(hairline, other.hairline, t),
      divider: _lerp(divider, other.divider, t),
      border: _lerp(border, other.border, t),
      focusBorder: _lerp(focusBorder, other.focusBorder, t),
      focusRing: _lerp(focusRing, other.focusRing, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

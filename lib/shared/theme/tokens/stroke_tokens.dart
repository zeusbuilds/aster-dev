import 'package:flutter/material.dart';

/// Stroke widths for borders, dividers, focus rings, and hairline art.
@immutable
class AsterStrokes extends ThemeExtension<AsterStrokes> {
  const AsterStrokes({
    this.hairline = 0.5,
    this.divider = 1,
    this.border = 1,
    this.selectionIndicator = 2,
    this.focusBorder = 1.5,
    this.focusRing = 3,
    this.progressIndicator = 2,
  });

  final double hairline;
  final double divider;
  final double border;
  final double selectionIndicator;
  final double focusBorder;
  final double focusRing;
  final double progressIndicator;

  @override
  AsterStrokes copyWith({
    double? hairline,
    double? divider,
    double? border,
    double? selectionIndicator,
    double? focusBorder,
    double? focusRing,
    double? progressIndicator,
  }) {
    return AsterStrokes(
      hairline: hairline ?? this.hairline,
      divider: divider ?? this.divider,
      border: border ?? this.border,
      selectionIndicator: selectionIndicator ?? this.selectionIndicator,
      focusBorder: focusBorder ?? this.focusBorder,
      focusRing: focusRing ?? this.focusRing,
      progressIndicator: progressIndicator ?? this.progressIndicator,
    );
  }

  @override
  AsterStrokes lerp(ThemeExtension<AsterStrokes>? other, double t) {
    if (other is! AsterStrokes) return this;
    return AsterStrokes(
      hairline: _lerp(hairline, other.hairline, t),
      divider: _lerp(divider, other.divider, t),
      border: _lerp(border, other.border, t),
      selectionIndicator: _lerp(
        selectionIndicator,
        other.selectionIndicator,
        t,
      ),
      focusBorder: _lerp(focusBorder, other.focusBorder, t),
      focusRing: _lerp(focusRing, other.focusRing, t),
      progressIndicator: _lerp(progressIndicator, other.progressIndicator, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

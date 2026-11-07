import 'package:flutter/material.dart';

/// Icon sizes and icon-affordance measurements.
///
/// Keep this separate from spacing so an icon decision cannot be confused with a
/// layout gap that happens to have the same number.
@immutable
class AsterIconography extends ThemeExtension<AsterIconography> {
  const AsterIconography({
    this.xxs = 12,
    this.xs = 18,
    this.sm = 20,
    this.md = 24,
    this.lg = 36,
    this.xl = 44,
    this.scanControlGlyph = 16,
  });

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double scanControlGlyph;

  @override
  AsterIconography copyWith({
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? scanControlGlyph,
  }) {
    return AsterIconography(
      xxs: xxs ?? this.xxs,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      scanControlGlyph: scanControlGlyph ?? this.scanControlGlyph,
    );
  }

  @override
  AsterIconography lerp(ThemeExtension<AsterIconography>? other, double t) {
    if (other is! AsterIconography) return this;
    return AsterIconography(
      xxs: _lerp(xxs, other.xxs, t),
      xs: _lerp(xs, other.xs, t),
      sm: _lerp(sm, other.sm, t),
      md: _lerp(md, other.md, t),
      lg: _lerp(lg, other.lg, t),
      xl: _lerp(xl, other.xl, t),
      scanControlGlyph: _lerp(scanControlGlyph, other.scanControlGlyph, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

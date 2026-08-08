import 'package:flutter/material.dart';

/// Layout distance scale.
///
/// This extension intentionally contains only gaps, padding, and safe-area
/// helpers. Component dimensions, icon sizes, and stroke widths live in their
/// own token systems.
@immutable
class AsterSpacing extends ThemeExtension<AsterSpacing> {
  const AsterSpacing({
    this.none = 0,
    this.xxs = 2,
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 20,
    this.xxl = 24,
    this.xxxl = 32,
    this.huge = 48,
    this.giant = 64,
    this.screenPadding = 20,
    this.sectionGap = 24,
    this.controlGap = 12,
  });

  final double none;
  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double xxxl;
  final double huge;
  final double giant;
  final double screenPadding;
  final double sectionGap;
  final double controlGap;

  @override
  AsterSpacing copyWith({
    double? none,
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? xxxl,
    double? huge,
    double? giant,
    double? screenPadding,
    double? sectionGap,
    double? controlGap,
  }) {
    return AsterSpacing(
      none: none ?? this.none,
      xxs: xxs ?? this.xxs,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      xxxl: xxxl ?? this.xxxl,
      huge: huge ?? this.huge,
      giant: giant ?? this.giant,
      screenPadding: screenPadding ?? this.screenPadding,
      sectionGap: sectionGap ?? this.sectionGap,
      controlGap: controlGap ?? this.controlGap,
    );
  }

  @override
  AsterSpacing lerp(ThemeExtension<AsterSpacing>? other, double t) {
    if (other is! AsterSpacing) return this;
    return AsterSpacing(
      none: _lerp(none, other.none, t),
      xxs: _lerp(xxs, other.xxs, t),
      xs: _lerp(xs, other.xs, t),
      sm: _lerp(sm, other.sm, t),
      md: _lerp(md, other.md, t),
      lg: _lerp(lg, other.lg, t),
      xl: _lerp(xl, other.xl, t),
      xxl: _lerp(xxl, other.xxl, t),
      xxxl: _lerp(xxxl, other.xxxl, t),
      huge: _lerp(huge, other.huge, t),
      giant: _lerp(giant, other.giant, t),
      screenPadding: _lerp(screenPadding, other.screenPadding, t),
      sectionGap: _lerp(sectionGap, other.sectionGap, t),
      controlGap: _lerp(controlGap, other.controlGap, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

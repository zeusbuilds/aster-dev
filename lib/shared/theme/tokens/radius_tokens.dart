import 'package:flutter/material.dart';

@immutable
class AsterRadii extends ThemeExtension<AsterRadii> {
  const AsterRadii({
    this.none = 0,
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 20,
    this.xxl = 24,
    this.sheet = 28,
    this.pill = 999,
  });

  final double none;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double sheet;
  final double pill;

  double get card => xxl;
  double get button => 18;
  double get input => md;
  double get badge => sm;

  @override
  AsterRadii copyWith({
    double? none,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? sheet,
    double? pill,
  }) {
    return AsterRadii(
      none: none ?? this.none,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      sheet: sheet ?? this.sheet,
      pill: pill ?? this.pill,
    );
  }

  @override
  AsterRadii lerp(ThemeExtension<AsterRadii>? other, double t) {
    if (other is! AsterRadii) return this;
    return AsterRadii(
      none: _lerp(none, other.none, t),
      xs: _lerp(xs, other.xs, t),
      sm: _lerp(sm, other.sm, t),
      md: _lerp(md, other.md, t),
      lg: _lerp(lg, other.lg, t),
      xl: _lerp(xl, other.xl, t),
      xxl: _lerp(xxl, other.xxl, t),
      sheet: _lerp(sheet, other.sheet, t),
      pill: _lerp(pill, other.pill, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

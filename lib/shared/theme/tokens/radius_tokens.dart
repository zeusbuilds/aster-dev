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
    this.card = 24,
    this.button = 18,
    this.input = 12,
    this.badge = 8,
    this.iconButton = 12,
    this.control = 16,
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
  final double card;
  final double button;
  final double input;
  final double badge;
  final double iconButton;
  final double control;

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
    double? card,
    double? button,
    double? input,
    double? badge,
    double? iconButton,
    double? control,
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
      card: card ?? this.card,
      button: button ?? this.button,
      input: input ?? this.input,
      badge: badge ?? this.badge,
      iconButton: iconButton ?? this.iconButton,
      control: control ?? this.control,
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
      card: _lerp(card, other.card, t),
      button: _lerp(button, other.button, t),
      input: _lerp(input, other.input, t),
      badge: _lerp(badge, other.badge, t),
      iconButton: _lerp(iconButton, other.iconButton, t),
      control: _lerp(control, other.control, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

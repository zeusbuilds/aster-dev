import 'package:flutter/material.dart';

@immutable
class AsterSpacing extends ThemeExtension<AsterSpacing> {
  const AsterSpacing({
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
    this.iconXs = 18,
    this.iconSm = 20,
    this.iconMd = 24,
    this.iconLg = 36,
    this.iconXl = 44,
    this.navOffset = 44,
    this.heroInset = 160,
  });

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
  final double iconXs;
  final double iconSm;
  final double iconMd;
  final double iconLg;
  final double iconXl;
  final double navOffset;
  final double heroInset;

  double topSafeRaw(BuildContext context) => MediaQuery.of(context).padding.top;
  double bottomSafeRaw(BuildContext context) =>
      MediaQuery.of(context).viewPadding.bottom;
  double topSafe(BuildContext context) => topSafeRaw(context) + lg;
  double bottomSafe(BuildContext context) => bottomSafeRaw(context) + lg;

  @override
  AsterSpacing copyWith({
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
    double? iconXs,
    double? iconSm,
    double? iconMd,
    double? iconLg,
    double? iconXl,
    double? navOffset,
    double? heroInset,
  }) {
    return AsterSpacing(
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
      iconXs: iconXs ?? this.iconXs,
      iconSm: iconSm ?? this.iconSm,
      iconMd: iconMd ?? this.iconMd,
      iconLg: iconLg ?? this.iconLg,
      iconXl: iconXl ?? this.iconXl,
      navOffset: navOffset ?? this.navOffset,
      heroInset: heroInset ?? this.heroInset,
    );
  }

  @override
  AsterSpacing lerp(ThemeExtension<AsterSpacing>? other, double t) {
    if (other is! AsterSpacing) return this;
    return AsterSpacing(
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
      iconXs: _lerp(iconXs, other.iconXs, t),
      iconSm: _lerp(iconSm, other.iconSm, t),
      iconMd: _lerp(iconMd, other.iconMd, t),
      iconLg: _lerp(iconLg, other.iconLg, t),
      iconXl: _lerp(iconXl, other.iconXl, t),
      navOffset: _lerp(navOffset, other.navOffset, t),
      heroInset: _lerp(heroInset, other.heroInset, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

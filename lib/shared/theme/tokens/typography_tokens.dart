import 'package:flutter/material.dart';

@immutable
class AsterTypography extends ThemeExtension<AsterTypography> {
  const AsterTypography({
    this.fontFamilyPrimary = 'DM Sans',
    this.fontFamilyNumeric = 'Public Sans',
  });

  final String fontFamilyPrimary;
  final String fontFamilyNumeric;

  @override
  AsterTypography copyWith({
    String? fontFamilyPrimary,
    String? fontFamilyNumeric,
  }) {
    return AsterTypography(
      fontFamilyPrimary: fontFamilyPrimary ?? this.fontFamilyPrimary,
      fontFamilyNumeric: fontFamilyNumeric ?? this.fontFamilyNumeric,
    );
  }

  @override
  AsterTypography lerp(ThemeExtension<AsterTypography>? other, double t) {
    if (other is! AsterTypography) return this;
    return t < 0.5 ? this : other;
  }
}

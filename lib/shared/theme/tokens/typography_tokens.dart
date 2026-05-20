import 'package:flutter/material.dart';

@immutable
class AsterTypography extends ThemeExtension<AsterTypography> {
  const AsterTypography({
    this.fontFamilyPrimary = 'DM Sans',
    this.fontFamilyMonospace = 'DM Mono',
    this.fontFamilyNumeric = 'Public Sans',
  });

  final String fontFamilyPrimary;
  final String fontFamilyMonospace;
  final String fontFamilyNumeric;

  @override
  AsterTypography copyWith({
    String? fontFamilyPrimary,
    String? fontFamilyMonospace,
    String? fontFamilyNumeric,
  }) {
    return AsterTypography(
      fontFamilyPrimary: fontFamilyPrimary ?? this.fontFamilyPrimary,
      fontFamilyMonospace: fontFamilyMonospace ?? this.fontFamilyMonospace,
      fontFamilyNumeric: fontFamilyNumeric ?? this.fontFamilyNumeric,
    );
  }

  @override
  AsterTypography lerp(ThemeExtension<AsterTypography>? other, double t) {
    return this;
  }
}

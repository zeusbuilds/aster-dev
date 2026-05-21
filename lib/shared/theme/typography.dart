import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'theme_context.dart';
import 'tokens/typography_tokens.dart';

class TypographySystem {
  TypographySystem._();

  static const _typography = AsterTypography();

  static TextTheme buildTextTheme({required Color onSurface}) {
    final base = GoogleFonts.dmSansTextTheme(ThemeData.light().textTheme);

    TextStyle style(
      double size,
      FontWeight weight,
      double height, {
      Color? color,
    }) {
      return GoogleFonts.dmSans(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: 0,
        color: color ?? onSurface,
      );
    }

    return base.copyWith(
      displayLarge: style(56, FontWeight.w700, 1.0),
      displayMedium: style(48, FontWeight.w700, 1.0),
      displaySmall: style(40, FontWeight.w700, 1.05),
      headlineLarge: style(32, FontWeight.w700, 1.15),
      headlineMedium: style(28, FontWeight.w700, 1.18),
      headlineSmall: style(24, FontWeight.w700, 1.2),
      titleLarge: style(22, FontWeight.w600, 1.25),
      titleMedium: style(18, FontWeight.w600, 1.3),
      titleSmall: style(14, FontWeight.w600, 1.35),
      labelLarge: style(16, FontWeight.w600, 1.25),
      labelMedium: style(14, FontWeight.w600, 1.25),
      labelSmall: style(12, FontWeight.w600, 1.25),
      bodyLarge: style(16, FontWeight.w400, 1.45),
      bodyMedium: style(14, FontWeight.w400, 1.45),
      bodySmall: style(12, FontWeight.w400, 1.45),
    );
  }

  static AsterTypography get typography => _typography;
}

extension NumericTextStyle on TextStyle {
  TextStyle toNumeric(BuildContext context) {
    return GoogleFonts.getFont(
      context.typography.fontFamilyNumeric,
      textStyle: this,
    );
  }
}

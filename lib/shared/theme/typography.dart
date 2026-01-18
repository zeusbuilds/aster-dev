import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography system using design tokens
///
/// This system follows industry best practices for design tokens:
/// - Base tokens for font families, weights, sizes, line heights, letter spacing
/// - Material Design 3 text styles built from base tokens
/// - Platform-agnostic approach for consistency across platforms
/// - Professional typography scale optimized for financial/crypto applications
class TypographySystem {
  TypographySystem._();

  /// Creates a TextTheme using design tokens from TypographyTokens
  ///
  /// This method builds composite typography styles by combining base tokens
  /// into semantic, reusable text styles following Material Design 3 patterns.
  /// Optimized for financial/crypto applications with clear hierarchy and readability.
  static TextTheme buildTextTheme({
    required TypographyTokens tokens,
    required Color onBackground,
  }) {
    // Get base text theme from Google Fonts using DM Sans
    final baseTextTheme = GoogleFonts.dmSansTextTheme(
      ThemeData.light().textTheme,
    );

    return baseTextTheme.copyWith(
      // Display Styles - Largest text, typically for hero sections, splash screens
      displayLarge: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size56, // 56px - Hero text, large amounts
        fontWeight: tokens.weightBold,
        lineHeight: tokens.lineHeightTight,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),
      displayMedium: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size48, // 48px - Secondary hero text
        fontWeight: tokens.weightBold,
        lineHeight: tokens.lineHeightTight,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),
      displaySmall: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size36, // 36px - Large section headers
        fontWeight: tokens.weightBold,
        lineHeight: tokens.lineHeightTight,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),

      // Headline Styles - Section headers and major headings
      headlineLarge: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size32, // 32px - Page titles, major sections
        fontWeight: tokens.weightBold,
        lineHeight: tokens.lineHeightSnug,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),
      headlineMedium: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size28, // 28px - Section headers
        fontWeight: tokens.weightBold,
        lineHeight: tokens.lineHeightSnug,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),
      headlineSmall: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size24, // 24px - Subsection headers
        fontWeight: tokens.weightBold,
        lineHeight: tokens.lineHeightSnug,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),

      // Title Styles - Subsection headers and card titles
      titleLarge: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size22, // 22px - Card titles, list item headers
        fontWeight: tokens.weightSemiBold,
        lineHeight: tokens.lineHeightNormal,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),
      titleMedium: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size18, // 18px - Secondary card titles
        fontWeight: tokens.weightSemiBold,
        lineHeight: tokens.lineHeightNormal,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),
      titleSmall: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size14, // 14px - Small titles, captions
        fontWeight: tokens.weightSemiBold,
        lineHeight: tokens.lineHeightNormal,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),

      // Label Styles - UI element labels (buttons, form fields, etc.)
      labelLarge: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size16, // 16px - Button text, form labels
        fontWeight: tokens.weightMedium,
        lineHeight: tokens.lineHeightNormal,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),
      labelMedium: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size14, // 14px - Secondary buttons, tabs
        fontWeight: tokens.weightMedium,
        lineHeight: tokens.lineHeightNormal,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),
      labelSmall: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size12, // 12px - Small labels, badges
        fontWeight: tokens.weightMedium,
        lineHeight: tokens.lineHeightNormal,
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),

      // Body Styles - Main content text
      bodyLarge: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size16, // 16px - Primary body text, descriptions
        fontWeight: tokens.weightRegular,
        lineHeight: tokens.lineHeightRelaxed, // 1.5 for readability
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),
      bodyMedium: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size14, // 14px - Secondary body text
        fontWeight: tokens.weightRegular,
        lineHeight: tokens.lineHeightRelaxed, // 1.5 for readability
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),
      bodySmall: buildStyle(
        fontFamily: tokens.fontFamilyPrimary,
        fontSize: tokens.size12, // 12px - Small body text, helper text
        fontWeight: tokens.weightRegular,
        lineHeight: tokens.lineHeightRelaxed, // 1.5 for readability
        letterSpacing: tokens.letterSpacingNormal,
        color: onBackground,
      ),
    );
  }

  /// Builds a TextStyle from design tokens
  ///
  /// This is a helper method that combines base tokens into a complete
  /// TextStyle, ensuring consistency across all text styles.
  static TextStyle buildStyle({
    required String fontFamily,
    required double fontSize,
    required FontWeight fontWeight,
    required double lineHeight,
    required double letterSpacing,
    required Color color,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: lineHeight,
      letterSpacing: letterSpacing,
      color: color,
    );
  }
}

/// Extension to easily switch to the numeric font
extension NumericTextStyle on TextStyle {
  TextStyle toNumeric(BuildContext context) {
    return GoogleFonts.getFont(
      context.typography.fontFamilyNumeric,
      textStyle: this,
    );
  }
}

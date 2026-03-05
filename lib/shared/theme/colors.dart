// ============================================================================
// COLOR CONSTANTS
// ============================================================================

import 'package:flutter/material.dart' show Color;

/// Brand Colors
class BrandColors {
  BrandColors._();
  static const Color brand1 = Color(0xFFE8F3FF);
  static const Color brand2 = Color(0xFFBEDAFF);
  static const Color brand3 = Color(0xFF94BFFF);
  static const Color brand4 = Color(0xFF6AA1FF);
  static const Color brand5 = Color(0xFF4080FF);
  static const Color brand6 = Color(0xFF165DFF);
  static const Color brand7 = Color(0xFF0E42D2);
}

/// Border Colors - Light Mode
class BorderColorsLight {
  BorderColorsLight._();
  static const Color border1 = Color(0xFFF2F3F5);
  static const Color border2 = Color(0xFFE5E6EB);
  static const Color border3 = Color(0xFFC9CDD4);
  static const Color border4 = Color(0xFF86909C);
}

/// Border Colors - Dark Mode
class BorderColorsDark {
  BorderColorsDark._();
  static const Color border1 = Color(0xFF4E5969); // Light border in dark mode
  static const Color border2 = Color(0xFF373B42); // Normal border
  static const Color border3 = Color(0xFF373B42); // Dark border
  static const Color border4 = Color(0xFF86909C); // Heavy border
}

/// Fill Colors - Light Mode
class FillColorsLight {
  FillColorsLight._();
  static const Color fill1 = Color(0xFFFFFFFF);
  static const Color fill2 = Color(0xFFF2F3F5);
  static const Color fill3 = Color(0xFFE5E6EB);
  static const Color fill4 = Color(0xFFC9CDD4);
  static const Color fill5 = Color(0xFF4E5969);
  static const Color fill6 = Color(0xFF000000);
}

/// Fill Colors - Dark Mode
class FillColorsDark {
  FillColorsDark._();
  static const Color fill1 = Color(0xFF000000); // Background
  static const Color fill2 = Color(0xFF2B2F36); // Surface
  static const Color fill3 = Color(0xFF373B42); // Surface variant
  static const Color fill4 = Color(0xFF4E5969); // Heavy fill
  static const Color fill5 = Color(0xFF86909C); // Emphasis fill
  static const Color fill6 = Color(0xFFFFFFFF);
}

/// Text Colors - Light Mode
class TextColorsLight {
  TextColorsLight._();
  static const Color text1 = Color(0xFF1D2129);
  static const Color text2 = Color(0xFF4E5969);
  static const Color text3 = Color(0xFF86909C);
  static const Color text4 = Color(0xFFC9CDD4);
  static const Color text5 = Color(0xFFFFFFFF);
}

/// Text Colors - Dark Mode
class TextColorsDark {
  TextColorsDark._();
  static const Color text1 = Color(0xFFF2F3F5); // Primary text
  static const Color text2 = Color(0xFFC9CDD4); // Secondary text
  static const Color text3 = Color(0xFF86909C); // Tertiary text
  static const Color text4 = Color(0xFF4E5969); // Disabled text
  static const Color text5 = Color(0xFFFFFFFF); // White text
}

/// Success Colors
class SuccessColors {
  SuccessColors._();
  static const Color success1 = Color(0xFFE8F8E5);
  static const Color success2 = Color(0xFFAFF0B5);
  static const Color success3 = Color(0xFF7BE188);
  static const Color success5 = Color(0xFF23C343);
  static const Color success6 = Color(0xFF00B42A);
  static const Color success7 = Color(0xFF009A29);
}

/// Warning Colors
class WarningColors {
  WarningColors._();
  static const Color warning1 = Color(0xFFFFF7E8);
  static const Color warning2 = Color(0xFFFFE4BA);
  static const Color warning3 = Color(0xFFFFCF8B);
  static const Color warning5 = Color(0xFFFF9A2E);
  static const Color warning6 = Color(0xFFFF7D00);
  static const Color warning7 = Color(0xFFD25F00);
}

/// Danger Colors
class DangerColors {
  DangerColors._();
  static const Color danger1 = Color(0xFFFFECE8);
  static const Color danger2 = Color(0xFFFDCDC5);
  static const Color danger3 = Color(0xFFFBACA3);
  static const Color danger5 = Color(0xFFF76560);
  static const Color danger6 = Color(0xFFF53F3F);
  static const Color danger7 = Color(0xFFCB2634);
}

// ============================================================================
// COLOR CONSTANTS
// ============================================================================

import 'package:flutter/material.dart' show Color;

/// Brand Colors
class BrandColors {
  BrandColors._();
  static const Color brand1 = Color(0xFFE8F3FF); // 浅色/白底悬浮
  static const Color brand2 = Color(0xFFBEDAFF); // 文字禁用
  static const Color brand3 = Color(0xFF94BFFF); // 一般禁用
  static const Color brand4 = Color(0xFF6AA1FF); // 特殊场景
  static const Color brand5 = Color(0xFF4080FF); // 悬浮
  static const Color brand6 = Color(0xFF165DFF); // 常规
  static const Color brand7 = Color(0xFF0E42D2); // 点击
}

/// Border Colors - Light Mode
class BorderColorsLight {
  BorderColorsLight._();
  static const Color border1 = Color(0xFFF2F3F5); // 浅
  static const Color border2 = Color(0xFFE5E6EB); // 一般
  static const Color border3 = Color(0xFFC9CDD4); // 深/悬浮
  static const Color border4 = Color(0xFF86909C); // 重/按钮描边
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
  static const Color fill1 = Color(0xFFFFFFFF); // 浅/禁用
  static const Color fill2 = Color(0xFFF2F3F5); // 一般/常规/白底悬浮
  static const Color fill3 = Color(0xFFE5E6EB); // 深/灰底悬浮
  static const Color fill4 = Color(0xFFC9CDD4); // 重/特殊场景
  static const Color fill5 = Color(0xFF4E5969); // 强调/图标/特殊场景
}

/// Fill Colors - Dark Mode
class FillColorsDark {
  FillColorsDark._();
  static const Color fill1 = Color(0xFF000000); // Background
  static const Color fill2 = Color(0xFF2B2F36); // Surface
  static const Color fill3 = Color(0xFF373B42); // Surface variant
  static const Color fill4 = Color(0xFF4E5969); // Heavy fill
  static const Color fill5 = Color(0xFF86909C); // Emphasis fill
}

/// Text Colors - Light Mode
class TextColorsLight {
  TextColorsLight._();
  static const Color text1 = Color(0xFF1D2129); // 强调/正文标题
  static const Color text2 = Color(0xFF4E5969); // 次强调/正文标题
  static const Color text3 = Color(0xFF86909C); // 次要信息
  static const Color text4 = Color(0xFFC9CDD4); // 置灰信息
  static const Color text5 = Color(0xFFFFFFFF); // 纯白文字
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
  static const Color success1 = Color(0xFFE8F8E5); // 浅色背景
  static const Color success2 = Color(0xFFAFF0B5); // 特殊场景
  static const Color success3 = Color(0xFF7BE188); // 禁用
  static const Color success5 = Color(0xFF23C343); // 悬浮
  static const Color success6 = Color(0xFF00B42A); // 常规
  static const Color success7 = Color(0xFF009A29); // 点击
}

/// Warning Colors
class WarningColors {
  WarningColors._();
  static const Color warning1 = Color(0xFFFFF7E8); // 浅色背景
  static const Color warning2 = Color(0xFFFFE4BA); // 特殊场景
  static const Color warning3 = Color(0xFFFFCF8B); // 禁用
  static const Color warning5 = Color(0xFFFF9A2E); // 悬浮
  static const Color warning6 = Color(0xFFFF7D00); // 常规
  static const Color warning7 = Color(0xFFD25F00); // 点击
}

/// Danger Colors
class DangerColors {
  DangerColors._();
  static const Color danger1 = Color(0xFFFFECE8); // 浅色背景
  static const Color danger2 = Color(0xFFFDCDC5); // 特殊场景
  static const Color danger3 = Color(0xFFFBACA3); // 禁用
  static const Color danger5 = Color(0xFFF76560); // 悬浮
  static const Color danger6 = Color(0xFFF53F3F); // 常规
  static const Color danger7 = Color(0xFFCB2634); // 点击
}

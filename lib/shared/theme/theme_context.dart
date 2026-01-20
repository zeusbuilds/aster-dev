import 'package:flutter/material.dart';

import 'tokens/color_tokens.dart';
import 'tokens/radius_tokens.dart';
import 'tokens/shadow_tokens.dart';
import 'tokens/spacing_tokens.dart';
import 'tokens/typography_tokens.dart';

/// Extension on BuildContext to easily access theme tokens
extension ThemeContext on BuildContext {
  /// Get the current ThemeData
  ThemeData get theme => Theme.of(this);

  /// Get the current TextTheme
  TextTheme get textTheme => theme.textTheme;

  /// Get the ColorTokens (automatically switches between light and dark based on theme)
  ///
  /// Example: context.colors.brand6 or context.colors.text1
  ColorTokens get colors => theme.brightness == Brightness.dark
      ? ColorTokens.dark
      : ColorTokens.light;

  /// Get the SpacingTokens
  ///
  /// Example: context.spacing.spacing16 or context.spacing.spacing24
  SpacingTokens get spacing => SpacingTokens(
    bottomSafeHeightDynamicRaw: MediaQuery.of(this).padding.bottom,
    topSafeHeightDynamicRaw: MediaQuery.of(this).padding.top,
    bottomSafeHeightRaw: MediaQuery.of(this).viewPadding.bottom,
    topSafeHeightRaw: MediaQuery.of(this).viewPadding.top,
    bottomSafeHeightDynamic: MediaQuery.of(this).padding.bottom + 16,
    topSafeHeightDynamic: MediaQuery.of(this).padding.top + 16,
    bottomSafeHeight: MediaQuery.of(this).viewPadding.bottom + 16,
    topSafeHeight: MediaQuery.of(this).viewPadding.top + 16,
  );

  /// Get the RadiusTokens
  ///
  /// Example: context.radius.radius8 or context.radius.radius16
  RadiusTokens get radius => const RadiusTokens();

  /// Get the TypographyTokens
  ///
  /// Example: context.typography.size16 or context.typography.weightBold
  TypographyTokens get typography => const TypographyTokens();

  /// Get the ShadowTokens
  ///
  /// Example: context.shadows.shadow4 or context.shadows.shadowCard
  ShadowTokens get shadows => const ShadowTokens();
}

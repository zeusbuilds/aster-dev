import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../shared.dart';

/// Loader color variant
enum LoaderColorVariant {
  /// Primary color from theme
  primary,

  /// Secondary color from theme
  secondary,

  /// On surface color (for use on colored backgrounds)
  onSurface,

  /// Custom color
  custom,
}

/// Loader size preset
enum LoaderSize {
  /// Small size - 16px
  small,

  /// Medium size - 24px
  medium,

  /// Large size - 32px
  large,

  /// Extra large size - 48px
  extraLarge,
}

/// Professional loader widget with platform-specific indicators
///
/// Uses CircularProgressIndicator on Android and CupertinoActivityIndicator on iOS
class CustomLoader extends StatelessWidget {
  /// Color variant for the loader
  final LoaderColorVariant colorVariant;

  /// Custom color (only used when colorVariant is custom)
  final Color? customColor;

  /// Size of the loader
  final LoaderSize size;

  /// Custom size in pixels (overrides size if provided)
  final double? customSize;

  /// Stroke width for Android CircularProgressIndicator (default: 2.0)
  final double? strokeWidth;

  const CustomLoader({
    super.key,
    this.colorVariant = LoaderColorVariant.primary,
    this.customColor,
    this.size = LoaderSize.medium,
    this.customSize,
    this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Determine the color based on variant
    final color = _getColor(colors);

    // Determine the size
    final loaderSize = customSize ?? _getSize();

    // Use platform-specific indicator
    if (Platform.isIOS) {
      return CupertinoActivityIndicator(radius: loaderSize / 2, color: color);
    } else {
      return SizedBox(
        width: loaderSize,
        height: loaderSize,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth ?? 2.0,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }
  }

  /// Gets the color based on the variant
  Color _getColor(ColorTokens colors) {
    switch (colorVariant) {
      case LoaderColorVariant.primary:
        return colors.brand6;
      case LoaderColorVariant.secondary:
        return colors.brand2;
      case LoaderColorVariant.onSurface:
        return colors.text1;
      case LoaderColorVariant.custom:
        return customColor ?? colors.brand6;
    }
  }

  /// Gets the size based on the preset
  double _getSize() {
    switch (size) {
      case LoaderSize.small:
        return 16.0; // spacing16
      case LoaderSize.medium:
        return 24.0; // spacing24
      case LoaderSize.large:
        return 32.0; // spacing32
      case LoaderSize.extraLarge:
        return 48.0; // spacing48
    }
  }
}

import 'package:flutter/material.dart';

/// Component-specific measurements that are not general-purpose spacing.
@immutable
class AsterComponentMetrics extends ThemeExtension<AsterComponentMetrics> {
  const AsterComponentMetrics({
    this.buttonHeight = 48,
    this.compactButtonHeight = 40,
    this.homeHeroHeightFactor = 0.4,
    this.scanFrameSizeFactor = 0.7,
    this.onboardingIconGridGap = 6,
    this.onboardingIconBlurSigma = 14,
    this.brandMeshBlurSigma = 20,
    this.recoveryWordGridAspectRatio = 4.5,
    this.marketTextureSize = 128,
    this.marketBadgeDotSize = 20,
    this.borderWidth = 1,
    this.focusBorderWidth = 1.5,
    this.sliderThumbRadius = 8,
    this.sliderOverlayRadius = 16,
    this.swapDetailSlideDistance = 50,
  });

  final double buttonHeight;
  final double compactButtonHeight;
  final double homeHeroHeightFactor;
  final double scanFrameSizeFactor;
  final double onboardingIconGridGap;
  final double onboardingIconBlurSigma;
  final double brandMeshBlurSigma;
  final double recoveryWordGridAspectRatio;
  final double marketTextureSize;
  final double marketBadgeDotSize;
  final double borderWidth;
  final double focusBorderWidth;
  final double sliderThumbRadius;
  final double sliderOverlayRadius;
  final double swapDetailSlideDistance;

  @override
  AsterComponentMetrics copyWith({
    double? buttonHeight,
    double? compactButtonHeight,
    double? homeHeroHeightFactor,
    double? scanFrameSizeFactor,
    double? onboardingIconGridGap,
    double? onboardingIconBlurSigma,
    double? brandMeshBlurSigma,
    double? recoveryWordGridAspectRatio,
    double? marketTextureSize,
    double? marketBadgeDotSize,
    double? borderWidth,
    double? focusBorderWidth,
    double? sliderThumbRadius,
    double? sliderOverlayRadius,
    double? swapDetailSlideDistance,
  }) {
    return AsterComponentMetrics(
      buttonHeight: buttonHeight ?? this.buttonHeight,
      compactButtonHeight: compactButtonHeight ?? this.compactButtonHeight,
      homeHeroHeightFactor: homeHeroHeightFactor ?? this.homeHeroHeightFactor,
      scanFrameSizeFactor: scanFrameSizeFactor ?? this.scanFrameSizeFactor,
      onboardingIconGridGap:
          onboardingIconGridGap ?? this.onboardingIconGridGap,
      onboardingIconBlurSigma:
          onboardingIconBlurSigma ?? this.onboardingIconBlurSigma,
      brandMeshBlurSigma: brandMeshBlurSigma ?? this.brandMeshBlurSigma,
      recoveryWordGridAspectRatio:
          recoveryWordGridAspectRatio ?? this.recoveryWordGridAspectRatio,
      marketTextureSize: marketTextureSize ?? this.marketTextureSize,
      marketBadgeDotSize: marketBadgeDotSize ?? this.marketBadgeDotSize,
      borderWidth: borderWidth ?? this.borderWidth,
      focusBorderWidth: focusBorderWidth ?? this.focusBorderWidth,
      sliderThumbRadius: sliderThumbRadius ?? this.sliderThumbRadius,
      sliderOverlayRadius: sliderOverlayRadius ?? this.sliderOverlayRadius,
      swapDetailSlideDistance:
          swapDetailSlideDistance ?? this.swapDetailSlideDistance,
    );
  }

  @override
  AsterComponentMetrics lerp(
    ThemeExtension<AsterComponentMetrics>? other,
    double t,
  ) {
    if (other is! AsterComponentMetrics) return this;
    return AsterComponentMetrics(
      buttonHeight: _lerp(buttonHeight, other.buttonHeight, t),
      compactButtonHeight: _lerp(
        compactButtonHeight,
        other.compactButtonHeight,
        t,
      ),
      homeHeroHeightFactor: _lerp(
        homeHeroHeightFactor,
        other.homeHeroHeightFactor,
        t,
      ),
      scanFrameSizeFactor: _lerp(
        scanFrameSizeFactor,
        other.scanFrameSizeFactor,
        t,
      ),
      onboardingIconGridGap: _lerp(
        onboardingIconGridGap,
        other.onboardingIconGridGap,
        t,
      ),
      onboardingIconBlurSigma: _lerp(
        onboardingIconBlurSigma,
        other.onboardingIconBlurSigma,
        t,
      ),
      brandMeshBlurSigma: _lerp(
        brandMeshBlurSigma,
        other.brandMeshBlurSigma,
        t,
      ),
      recoveryWordGridAspectRatio: _lerp(
        recoveryWordGridAspectRatio,
        other.recoveryWordGridAspectRatio,
        t,
      ),
      marketTextureSize: _lerp(marketTextureSize, other.marketTextureSize, t),
      marketBadgeDotSize: _lerp(
        marketBadgeDotSize,
        other.marketBadgeDotSize,
        t,
      ),
      borderWidth: _lerp(borderWidth, other.borderWidth, t),
      focusBorderWidth: _lerp(focusBorderWidth, other.focusBorderWidth, t),
      sliderThumbRadius: _lerp(sliderThumbRadius, other.sliderThumbRadius, t),
      sliderOverlayRadius: _lerp(
        sliderOverlayRadius,
        other.sliderOverlayRadius,
        t,
      ),
      swapDetailSlideDistance: _lerp(
        swapDetailSlideDistance,
        other.swapDetailSlideDistance,
        t,
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

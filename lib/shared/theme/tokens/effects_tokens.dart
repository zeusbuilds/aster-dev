import 'package:flutter/material.dart';

/// Reusable visual effects that are not colors, spacing, motion, or state
/// layers.
@immutable
class AsterEffects extends ThemeExtension<AsterEffects> {
  const AsterEffects({
    this.brandContentStrongOpacity = 0.9,
    this.brandContentMutedOpacity = 0.75,
    this.brandGlassBorderOpacity = 0.1,
    this.onboardingIconTileStrongOpacity = 0.3,
    this.onboardingIconTileFaintOpacity = 0.05,
    this.onboardingStepIndicatorInactiveOpacity = 0.35,
    this.bitcoinIconOpacity = 0.8,
    this.scanControlSurfaceOpacity = 0.4,
    this.scanSecondaryContentOpacity = 0.75,
    this.marketShadowOpacity = 0.16,
    this.marketPillSurfaceOpacity = 0.15,
    this.marketPillDotOpacity = 0.5,
    this.artNoiseOpacity = 0.05,
    this.artNoiseTintOpacity = 0.5,
    this.loaderBreathingMinimumOpacity = 0.35,
    this.loaderBreathingMaximumOpacity = 1,
    this.loaderTrailStrongOpacity = 0.8,
    this.loaderTrailMediumOpacity = 0.55,
    this.loaderTrailWeakOpacity = 0.3,
    this.loaderPlusTrailWeakOpacity = 0.5,
    this.chartLoadingBaseOpacity = 0.5,
    this.chartLoadingOpacityAmplitude = 0.3,
    this.chartContentOpacity = 0.8,
  });

  final double brandContentStrongOpacity;
  final double brandContentMutedOpacity;
  final double brandGlassBorderOpacity;

  final double onboardingIconTileStrongOpacity;
  final double onboardingIconTileFaintOpacity;
  final double onboardingStepIndicatorInactiveOpacity;
  final double bitcoinIconOpacity;
  final double scanControlSurfaceOpacity;
  final double scanSecondaryContentOpacity;
  final double marketShadowOpacity;
  final double marketPillSurfaceOpacity;
  final double marketPillDotOpacity;
  final double artNoiseOpacity;
  final double artNoiseTintOpacity;
  final double loaderBreathingMinimumOpacity;
  final double loaderBreathingMaximumOpacity;
  final double loaderTrailStrongOpacity;
  final double loaderTrailMediumOpacity;
  final double loaderTrailWeakOpacity;
  final double loaderPlusTrailWeakOpacity;
  final double chartLoadingBaseOpacity;
  final double chartLoadingOpacityAmplitude;
  final double chartContentOpacity;

  @override
  AsterEffects copyWith({
    double? brandContentStrongOpacity,
    double? brandContentMutedOpacity,
    double? brandGlassBorderOpacity,
    double? onboardingIconTileStrongOpacity,
    double? onboardingIconTileFaintOpacity,
    double? onboardingStepIndicatorInactiveOpacity,
    double? bitcoinIconOpacity,
    double? scanControlSurfaceOpacity,
    double? scanSecondaryContentOpacity,
    double? marketShadowOpacity,
    double? marketPillSurfaceOpacity,
    double? marketPillDotOpacity,
    double? artNoiseOpacity,
    double? artNoiseTintOpacity,
    double? loaderBreathingMinimumOpacity,
    double? loaderBreathingMaximumOpacity,
    double? loaderTrailStrongOpacity,
    double? loaderTrailMediumOpacity,
    double? loaderTrailWeakOpacity,
    double? loaderPlusTrailWeakOpacity,
    double? chartLoadingBaseOpacity,
    double? chartLoadingOpacityAmplitude,
    double? chartContentOpacity,
  }) {
    return AsterEffects(
      brandContentStrongOpacity:
          brandContentStrongOpacity ?? this.brandContentStrongOpacity,
      brandContentMutedOpacity:
          brandContentMutedOpacity ?? this.brandContentMutedOpacity,
      brandGlassBorderOpacity:
          brandGlassBorderOpacity ?? this.brandGlassBorderOpacity,
      onboardingIconTileStrongOpacity:
          onboardingIconTileStrongOpacity ??
          this.onboardingIconTileStrongOpacity,
      onboardingIconTileFaintOpacity:
          onboardingIconTileFaintOpacity ?? this.onboardingIconTileFaintOpacity,
      onboardingStepIndicatorInactiveOpacity:
          onboardingStepIndicatorInactiveOpacity ??
          this.onboardingStepIndicatorInactiveOpacity,
      bitcoinIconOpacity: bitcoinIconOpacity ?? this.bitcoinIconOpacity,
      scanControlSurfaceOpacity:
          scanControlSurfaceOpacity ?? this.scanControlSurfaceOpacity,
      scanSecondaryContentOpacity:
          scanSecondaryContentOpacity ?? this.scanSecondaryContentOpacity,
      marketShadowOpacity: marketShadowOpacity ?? this.marketShadowOpacity,
      marketPillSurfaceOpacity:
          marketPillSurfaceOpacity ?? this.marketPillSurfaceOpacity,
      marketPillDotOpacity: marketPillDotOpacity ?? this.marketPillDotOpacity,
      artNoiseOpacity: artNoiseOpacity ?? this.artNoiseOpacity,
      artNoiseTintOpacity: artNoiseTintOpacity ?? this.artNoiseTintOpacity,
      loaderBreathingMinimumOpacity:
          loaderBreathingMinimumOpacity ?? this.loaderBreathingMinimumOpacity,
      loaderBreathingMaximumOpacity:
          loaderBreathingMaximumOpacity ?? this.loaderBreathingMaximumOpacity,
      loaderTrailStrongOpacity:
          loaderTrailStrongOpacity ?? this.loaderTrailStrongOpacity,
      loaderTrailMediumOpacity:
          loaderTrailMediumOpacity ?? this.loaderTrailMediumOpacity,
      loaderTrailWeakOpacity:
          loaderTrailWeakOpacity ?? this.loaderTrailWeakOpacity,
      loaderPlusTrailWeakOpacity:
          loaderPlusTrailWeakOpacity ?? this.loaderPlusTrailWeakOpacity,
      chartLoadingBaseOpacity:
          chartLoadingBaseOpacity ?? this.chartLoadingBaseOpacity,
      chartLoadingOpacityAmplitude:
          chartLoadingOpacityAmplitude ?? this.chartLoadingOpacityAmplitude,
      chartContentOpacity: chartContentOpacity ?? this.chartContentOpacity,
    );
  }

  @override
  AsterEffects lerp(ThemeExtension<AsterEffects>? other, double t) {
    if (other is! AsterEffects) return this;
    return AsterEffects(
      brandContentStrongOpacity: _lerp(
        brandContentStrongOpacity,
        other.brandContentStrongOpacity,
        t,
      ),
      brandContentMutedOpacity: _lerp(
        brandContentMutedOpacity,
        other.brandContentMutedOpacity,
        t,
      ),
      brandGlassBorderOpacity: _lerp(
        brandGlassBorderOpacity,
        other.brandGlassBorderOpacity,
        t,
      ),
      onboardingIconTileStrongOpacity: _lerp(
        onboardingIconTileStrongOpacity,
        other.onboardingIconTileStrongOpacity,
        t,
      ),
      onboardingIconTileFaintOpacity: _lerp(
        onboardingIconTileFaintOpacity,
        other.onboardingIconTileFaintOpacity,
        t,
      ),
      onboardingStepIndicatorInactiveOpacity: _lerp(
        onboardingStepIndicatorInactiveOpacity,
        other.onboardingStepIndicatorInactiveOpacity,
        t,
      ),
      bitcoinIconOpacity: _lerp(
        bitcoinIconOpacity,
        other.bitcoinIconOpacity,
        t,
      ),
      scanControlSurfaceOpacity: _lerp(
        scanControlSurfaceOpacity,
        other.scanControlSurfaceOpacity,
        t,
      ),
      scanSecondaryContentOpacity: _lerp(
        scanSecondaryContentOpacity,
        other.scanSecondaryContentOpacity,
        t,
      ),
      marketShadowOpacity: _lerp(
        marketShadowOpacity,
        other.marketShadowOpacity,
        t,
      ),
      marketPillSurfaceOpacity: _lerp(
        marketPillSurfaceOpacity,
        other.marketPillSurfaceOpacity,
        t,
      ),
      marketPillDotOpacity: _lerp(
        marketPillDotOpacity,
        other.marketPillDotOpacity,
        t,
      ),
      artNoiseOpacity: _lerp(artNoiseOpacity, other.artNoiseOpacity, t),
      artNoiseTintOpacity: _lerp(
        artNoiseTintOpacity,
        other.artNoiseTintOpacity,
        t,
      ),
      loaderBreathingMinimumOpacity: _lerp(
        loaderBreathingMinimumOpacity,
        other.loaderBreathingMinimumOpacity,
        t,
      ),
      loaderBreathingMaximumOpacity: _lerp(
        loaderBreathingMaximumOpacity,
        other.loaderBreathingMaximumOpacity,
        t,
      ),
      loaderTrailStrongOpacity: _lerp(
        loaderTrailStrongOpacity,
        other.loaderTrailStrongOpacity,
        t,
      ),
      loaderTrailMediumOpacity: _lerp(
        loaderTrailMediumOpacity,
        other.loaderTrailMediumOpacity,
        t,
      ),
      loaderTrailWeakOpacity: _lerp(
        loaderTrailWeakOpacity,
        other.loaderTrailWeakOpacity,
        t,
      ),
      loaderPlusTrailWeakOpacity: _lerp(
        loaderPlusTrailWeakOpacity,
        other.loaderPlusTrailWeakOpacity,
        t,
      ),
      chartLoadingBaseOpacity: _lerp(
        chartLoadingBaseOpacity,
        other.chartLoadingBaseOpacity,
        t,
      ),
      chartLoadingOpacityAmplitude: _lerp(
        chartLoadingOpacityAmplitude,
        other.chartLoadingOpacityAmplitude,
        t,
      ),
      chartContentOpacity: _lerp(
        chartContentOpacity,
        other.chartContentOpacity,
        t,
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

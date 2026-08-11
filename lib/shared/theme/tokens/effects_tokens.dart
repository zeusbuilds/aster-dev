import 'package:flutter/material.dart';

/// Reusable visual effects that are not colors, spacing, motion, or state
/// layers.
@immutable
class AsterEffects extends ThemeExtension<AsterEffects> {
  const AsterEffects({
    this.brandContentStrongOpacity = 0.9,
    this.brandContentMutedOpacity = 0.75,
    this.brandContentSubtleOpacity = 0.7,
    this.brandIndicatorInactiveOpacity = 0.35,
    this.brandGlassSurfaceOpacity = 0.15,
    this.brandGlassBorderOpacity = 0.1,
    this.onboardingIconTileStrongOpacity = 0.3,
    this.onboardingIconTileFaintOpacity = 0.05,
    this.bitcoinIconOpacity = 0.8,
    this.scanScrimStrongOpacity = 0.75,
    this.scanScrimMediumOpacity = 0.65,
    this.scanControlSurfaceOpacity = 0.4,
    this.scanAvatarSurfaceOpacity = 0.25,
    this.marketShadowOpacity = 0.16,
    this.marketContentMutedOpacity = 0.75,
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
  final double brandContentSubtleOpacity;
  final double brandIndicatorInactiveOpacity;
  final double brandGlassSurfaceOpacity;
  final double brandGlassBorderOpacity;
  final double onboardingIconTileStrongOpacity;
  final double onboardingIconTileFaintOpacity;
  final double bitcoinIconOpacity;
  final double scanScrimStrongOpacity;
  final double scanScrimMediumOpacity;
  final double scanControlSurfaceOpacity;
  final double scanAvatarSurfaceOpacity;
  final double marketShadowOpacity;
  final double marketContentMutedOpacity;
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
    double? brandContentSubtleOpacity,
    double? brandIndicatorInactiveOpacity,
    double? brandGlassSurfaceOpacity,
    double? brandGlassBorderOpacity,
    double? onboardingIconTileStrongOpacity,
    double? onboardingIconTileFaintOpacity,
    double? bitcoinIconOpacity,
    double? scanScrimStrongOpacity,
    double? scanScrimMediumOpacity,
    double? scanControlSurfaceOpacity,
    double? scanAvatarSurfaceOpacity,
    double? marketShadowOpacity,
    double? marketContentMutedOpacity,
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
      brandContentSubtleOpacity:
          brandContentSubtleOpacity ?? this.brandContentSubtleOpacity,
      brandIndicatorInactiveOpacity:
          brandIndicatorInactiveOpacity ?? this.brandIndicatorInactiveOpacity,
      brandGlassSurfaceOpacity:
          brandGlassSurfaceOpacity ?? this.brandGlassSurfaceOpacity,
      brandGlassBorderOpacity:
          brandGlassBorderOpacity ?? this.brandGlassBorderOpacity,
      onboardingIconTileStrongOpacity:
          onboardingIconTileStrongOpacity ??
          this.onboardingIconTileStrongOpacity,
      onboardingIconTileFaintOpacity:
          onboardingIconTileFaintOpacity ?? this.onboardingIconTileFaintOpacity,
      bitcoinIconOpacity: bitcoinIconOpacity ?? this.bitcoinIconOpacity,
      scanScrimStrongOpacity:
          scanScrimStrongOpacity ?? this.scanScrimStrongOpacity,
      scanScrimMediumOpacity:
          scanScrimMediumOpacity ?? this.scanScrimMediumOpacity,
      scanControlSurfaceOpacity:
          scanControlSurfaceOpacity ?? this.scanControlSurfaceOpacity,
      scanAvatarSurfaceOpacity:
          scanAvatarSurfaceOpacity ?? this.scanAvatarSurfaceOpacity,
      marketShadowOpacity: marketShadowOpacity ?? this.marketShadowOpacity,
      marketContentMutedOpacity:
          marketContentMutedOpacity ?? this.marketContentMutedOpacity,
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
      brandContentSubtleOpacity: _lerp(
        brandContentSubtleOpacity,
        other.brandContentSubtleOpacity,
        t,
      ),
      brandIndicatorInactiveOpacity: _lerp(
        brandIndicatorInactiveOpacity,
        other.brandIndicatorInactiveOpacity,
        t,
      ),
      brandGlassSurfaceOpacity: _lerp(
        brandGlassSurfaceOpacity,
        other.brandGlassSurfaceOpacity,
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
      bitcoinIconOpacity: _lerp(
        bitcoinIconOpacity,
        other.bitcoinIconOpacity,
        t,
      ),
      scanScrimStrongOpacity: _lerp(
        scanScrimStrongOpacity,
        other.scanScrimStrongOpacity,
        t,
      ),
      scanScrimMediumOpacity: _lerp(
        scanScrimMediumOpacity,
        other.scanScrimMediumOpacity,
        t,
      ),
      scanControlSurfaceOpacity: _lerp(
        scanControlSurfaceOpacity,
        other.scanControlSurfaceOpacity,
        t,
      ),
      scanAvatarSurfaceOpacity: _lerp(
        scanAvatarSurfaceOpacity,
        other.scanAvatarSurfaceOpacity,
        t,
      ),
      marketShadowOpacity: _lerp(
        marketShadowOpacity,
        other.marketShadowOpacity,
        t,
      ),
      marketContentMutedOpacity: _lerp(
        marketContentMutedOpacity,
        other.marketContentMutedOpacity,
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

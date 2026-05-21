import 'package:flutter/material.dart';

/// Reusable visual effects that are not colors, spacing, or motion.
@immutable
class AsterEffects extends ThemeExtension<AsterEffects> {
  const AsterEffects({
    this.disabledOpacity = 0.5,
    this.translucentSurfaceOpacity = 0.8,
    this.brandContentStrongOpacity = 0.9,
    this.brandContentMutedOpacity = 0.75,
    this.brandContentSubtleOpacity = 0.7,
    this.brandIndicatorInactiveOpacity = 0.35,
    this.brandGlassSurfaceOpacity = 0.15,
    this.brandGlassBorderOpacity = 0.1,
    this.bitcoinIconOpacity = 0.8,
    this.scanScrimStrongOpacity = 0.75,
    this.scanScrimMediumOpacity = 0.65,
    this.scanControlSurfaceOpacity = 0.4,
    this.scanAvatarSurfaceOpacity = 0.25,
    this.marketShadowOpacity = 0.16,
    this.marketContentMutedOpacity = 0.75,
    this.marketPillSurfaceOpacity = 0.15,
    this.marketPillDotOpacity = 0.5,
    this.selectedContainerOpacity = 0.5,
    this.primaryOverlayOpacity = 0.12,
    this.artNoiseOpacity = 0.05,
    this.artNoiseTintOpacity = 0.5,
  });

  final double disabledOpacity;
  final double translucentSurfaceOpacity;
  final double brandContentStrongOpacity;
  final double brandContentMutedOpacity;
  final double brandContentSubtleOpacity;
  final double brandIndicatorInactiveOpacity;
  final double brandGlassSurfaceOpacity;
  final double brandGlassBorderOpacity;
  final double bitcoinIconOpacity;
  final double scanScrimStrongOpacity;
  final double scanScrimMediumOpacity;
  final double scanControlSurfaceOpacity;
  final double scanAvatarSurfaceOpacity;
  final double marketShadowOpacity;
  final double marketContentMutedOpacity;
  final double marketPillSurfaceOpacity;
  final double marketPillDotOpacity;
  final double selectedContainerOpacity;
  final double primaryOverlayOpacity;
  final double artNoiseOpacity;
  final double artNoiseTintOpacity;

  @override
  AsterEffects copyWith({
    double? disabledOpacity,
    double? translucentSurfaceOpacity,
    double? brandContentStrongOpacity,
    double? brandContentMutedOpacity,
    double? brandContentSubtleOpacity,
    double? brandIndicatorInactiveOpacity,
    double? brandGlassSurfaceOpacity,
    double? brandGlassBorderOpacity,
    double? bitcoinIconOpacity,
    double? scanScrimStrongOpacity,
    double? scanScrimMediumOpacity,
    double? scanControlSurfaceOpacity,
    double? scanAvatarSurfaceOpacity,
    double? marketShadowOpacity,
    double? marketContentMutedOpacity,
    double? marketPillSurfaceOpacity,
    double? marketPillDotOpacity,
    double? selectedContainerOpacity,
    double? primaryOverlayOpacity,
    double? artNoiseOpacity,
    double? artNoiseTintOpacity,
  }) {
    return AsterEffects(
      disabledOpacity: disabledOpacity ?? this.disabledOpacity,
      translucentSurfaceOpacity:
          translucentSurfaceOpacity ?? this.translucentSurfaceOpacity,
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
      selectedContainerOpacity:
          selectedContainerOpacity ?? this.selectedContainerOpacity,
      primaryOverlayOpacity:
          primaryOverlayOpacity ?? this.primaryOverlayOpacity,
      artNoiseOpacity: artNoiseOpacity ?? this.artNoiseOpacity,
      artNoiseTintOpacity: artNoiseTintOpacity ?? this.artNoiseTintOpacity,
    );
  }

  @override
  AsterEffects lerp(ThemeExtension<AsterEffects>? other, double t) {
    if (other is! AsterEffects) return this;
    return AsterEffects(
      disabledOpacity: _lerp(disabledOpacity, other.disabledOpacity, t),
      translucentSurfaceOpacity: _lerp(
        translucentSurfaceOpacity,
        other.translucentSurfaceOpacity,
        t,
      ),
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
      selectedContainerOpacity: _lerp(
        selectedContainerOpacity,
        other.selectedContainerOpacity,
        t,
      ),
      primaryOverlayOpacity: _lerp(
        primaryOverlayOpacity,
        other.primaryOverlayOpacity,
        t,
      ),
      artNoiseOpacity: _lerp(artNoiseOpacity, other.artNoiseOpacity, t),
      artNoiseTintOpacity: _lerp(
        artNoiseTintOpacity,
        other.artNoiseTintOpacity,
        t,
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

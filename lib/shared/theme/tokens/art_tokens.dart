import 'package:flutter/material.dart';

/// Authored art-system measurements and recipes.
///
/// These values describe branded art composition. They are not general spacing
/// and should be used only by the visuals they name.
@immutable
class AsterArt extends ThemeExtension<AsterArt> {
  const AsterArt({
    this.homeMeshColumns = 5,
    this.homeMeshRows = 7,
    this.onboardingMeshColumns = 5,
    this.onboardingMeshRows = 7,
    this.brandMeshBlurSigma = 20,
    this.onboardingIconRows = 4,
    this.onboardingIconColumns = 7,
    this.onboardingIconGridGap = 6,
    this.onboardingIconBlurSigma = 14,
    this.splashLineInitialHeight = 8.5,
    this.splashLineMaximumHeight = 50,
    this.splashLineGapExtent = 1.3,
    this.splashLogoDiagonalRatio = 470 / 705,
    this.splashLogoThicknessRatio = 35 / 705,
    this.splashLogoHandoffProgress = 0.2,
    this.splashLogoDiagonalExitProgress = 0.98,
  });

  final int homeMeshColumns;
  final int homeMeshRows;
  final int onboardingMeshColumns;
  final int onboardingMeshRows;
  final double brandMeshBlurSigma;
  final int onboardingIconRows;
  final int onboardingIconColumns;
  final double onboardingIconGridGap;
  final double onboardingIconBlurSigma;
  final double splashLineInitialHeight;
  final double splashLineMaximumHeight;
  final double splashLineGapExtent;
  final double splashLogoDiagonalRatio;
  final double splashLogoThicknessRatio;
  final double splashLogoHandoffProgress;
  final double splashLogoDiagonalExitProgress;

  @override
  AsterArt copyWith({
    int? homeMeshColumns,
    int? homeMeshRows,
    int? onboardingMeshColumns,
    int? onboardingMeshRows,
    double? brandMeshBlurSigma,
    int? onboardingIconRows,
    int? onboardingIconColumns,
    double? onboardingIconGridGap,
    double? onboardingIconBlurSigma,
    double? splashLineInitialHeight,
    double? splashLineMaximumHeight,
    double? splashLineGapExtent,
    double? splashLogoDiagonalRatio,
    double? splashLogoThicknessRatio,
    double? splashLogoHandoffProgress,
    double? splashLogoDiagonalExitProgress,
  }) {
    return AsterArt(
      homeMeshColumns: homeMeshColumns ?? this.homeMeshColumns,
      homeMeshRows: homeMeshRows ?? this.homeMeshRows,
      onboardingMeshColumns:
          onboardingMeshColumns ?? this.onboardingMeshColumns,
      onboardingMeshRows: onboardingMeshRows ?? this.onboardingMeshRows,
      brandMeshBlurSigma: brandMeshBlurSigma ?? this.brandMeshBlurSigma,
      onboardingIconRows: onboardingIconRows ?? this.onboardingIconRows,
      onboardingIconColumns:
          onboardingIconColumns ?? this.onboardingIconColumns,
      onboardingIconGridGap:
          onboardingIconGridGap ?? this.onboardingIconGridGap,
      onboardingIconBlurSigma:
          onboardingIconBlurSigma ?? this.onboardingIconBlurSigma,
      splashLineInitialHeight:
          splashLineInitialHeight ?? this.splashLineInitialHeight,
      splashLineMaximumHeight:
          splashLineMaximumHeight ?? this.splashLineMaximumHeight,
      splashLineGapExtent: splashLineGapExtent ?? this.splashLineGapExtent,
      splashLogoDiagonalRatio:
          splashLogoDiagonalRatio ?? this.splashLogoDiagonalRatio,
      splashLogoThicknessRatio:
          splashLogoThicknessRatio ?? this.splashLogoThicknessRatio,
      splashLogoHandoffProgress:
          splashLogoHandoffProgress ?? this.splashLogoHandoffProgress,
      splashLogoDiagonalExitProgress:
          splashLogoDiagonalExitProgress ?? this.splashLogoDiagonalExitProgress,
    );
  }

  @override
  AsterArt lerp(ThemeExtension<AsterArt>? other, double t) {
    if (other is! AsterArt) return this;
    return AsterArt(
      homeMeshColumns: _lerpInt(homeMeshColumns, other.homeMeshColumns, t),
      homeMeshRows: _lerpInt(homeMeshRows, other.homeMeshRows, t),
      onboardingMeshColumns: _lerpInt(
        onboardingMeshColumns,
        other.onboardingMeshColumns,
        t,
      ),
      onboardingMeshRows: _lerpInt(
        onboardingMeshRows,
        other.onboardingMeshRows,
        t,
      ),
      brandMeshBlurSigma: _lerp(
        brandMeshBlurSigma,
        other.brandMeshBlurSigma,
        t,
      ),
      onboardingIconRows: _lerpInt(
        onboardingIconRows,
        other.onboardingIconRows,
        t,
      ),
      onboardingIconColumns: _lerpInt(
        onboardingIconColumns,
        other.onboardingIconColumns,
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
      splashLineInitialHeight: _lerp(
        splashLineInitialHeight,
        other.splashLineInitialHeight,
        t,
      ),
      splashLineMaximumHeight: _lerp(
        splashLineMaximumHeight,
        other.splashLineMaximumHeight,
        t,
      ),
      splashLineGapExtent: _lerp(
        splashLineGapExtent,
        other.splashLineGapExtent,
        t,
      ),
      splashLogoDiagonalRatio: _lerp(
        splashLogoDiagonalRatio,
        other.splashLogoDiagonalRatio,
        t,
      ),
      splashLogoThicknessRatio: _lerp(
        splashLogoThicknessRatio,
        other.splashLogoThicknessRatio,
        t,
      ),
      splashLogoHandoffProgress: _lerp(
        splashLogoHandoffProgress,
        other.splashLogoHandoffProgress,
        t,
      ),
      splashLogoDiagonalExitProgress: _lerp(
        splashLogoDiagonalExitProgress,
        other.splashLogoDiagonalExitProgress,
        t,
      ),
    );
  }

  static int _lerpInt(int a, int b, double t) => (a + (b - a) * t).round();
  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

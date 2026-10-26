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
    this.onboardingMeshColumns = 4,
    this.onboardingMeshRows = 4,
    this.brandMeshBlurSigma = 20,
    this.onboardingIconRows = 4,
    this.onboardingIconColumns = 7,
    this.onboardingIconHighlightRow = 1,
    this.onboardingIconHighlightColumn = 3,
    this.onboardingIconGridGap = 6,
    this.onboardingIconTileRadius = 4,
    this.onboardingIndicatorExpansionFactor = 4,
    this.onboardingWordmarkMarkHeight = 28,
    this.splashLineMaximumHeight = 50,
    this.splashLineGapExtent = 1.3,
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
  final int onboardingIconHighlightRow;
  final int onboardingIconHighlightColumn;
  final double onboardingIconGridGap;
  final double onboardingIconTileRadius;
  final double onboardingIndicatorExpansionFactor;
  final double onboardingWordmarkMarkHeight;
  final double splashLineMaximumHeight;
  final double splashLineGapExtent;
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
    int? onboardingIconHighlightRow,
    int? onboardingIconHighlightColumn,
    double? onboardingIconGridGap,
    double? onboardingIconTileRadius,
    double? onboardingIndicatorExpansionFactor,
    double? onboardingWordmarkMarkHeight,
    double? splashLineMaximumHeight,
    double? splashLineGapExtent,
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
      onboardingIconHighlightRow:
          onboardingIconHighlightRow ?? this.onboardingIconHighlightRow,
      onboardingIconHighlightColumn:
          onboardingIconHighlightColumn ?? this.onboardingIconHighlightColumn,
      onboardingIconGridGap:
          onboardingIconGridGap ?? this.onboardingIconGridGap,
      onboardingIconTileRadius:
          onboardingIconTileRadius ?? this.onboardingIconTileRadius,
      onboardingIndicatorExpansionFactor:
          onboardingIndicatorExpansionFactor ??
          this.onboardingIndicatorExpansionFactor,
      onboardingWordmarkMarkHeight:
          onboardingWordmarkMarkHeight ?? this.onboardingWordmarkMarkHeight,
      splashLineMaximumHeight:
          splashLineMaximumHeight ?? this.splashLineMaximumHeight,
      splashLineGapExtent: splashLineGapExtent ?? this.splashLineGapExtent,
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
      onboardingIconHighlightRow: _lerpInt(
        onboardingIconHighlightRow,
        other.onboardingIconHighlightRow,
        t,
      ),
      onboardingIconHighlightColumn: _lerpInt(
        onboardingIconHighlightColumn,
        other.onboardingIconHighlightColumn,
        t,
      ),
      onboardingIconGridGap: _lerp(
        onboardingIconGridGap,
        other.onboardingIconGridGap,
        t,
      ),
      onboardingIconTileRadius: _lerp(
        onboardingIconTileRadius,
        other.onboardingIconTileRadius,
        t,
      ),
      onboardingIndicatorExpansionFactor: _lerp(
        onboardingIndicatorExpansionFactor,
        other.onboardingIndicatorExpansionFactor,
        t,
      ),
      onboardingWordmarkMarkHeight: _lerp(
        onboardingWordmarkMarkHeight,
        other.onboardingWordmarkMarkHeight,
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

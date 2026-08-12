import 'package:flutter/material.dart';

/// Component geometry that is not general-purpose spacing.
@immutable
class AsterComponentMetrics extends ThemeExtension<AsterComponentMetrics> {
  const AsterComponentMetrics({
    this.buttonHeight = 48,
    this.compactButtonHeight = 40,
    this.minTouchTarget = 48,
    this.appBarLeadingWidth = 48,
    this.floatingNavClearance = 64,
    this.homeHeroHeightFactor = 0.4,
    this.scanFrameSizeFactor = 0.7,
    this.scanFrameMaximumSize = 320,
    this.scanHeaderExtent = 172,
    this.recoveryWordGridAspectRatio = 4.5,
    this.marketTileMinHeight = 156,
    this.marketTextureSize = 128,
    this.marketBadgeDotSize = 20,
    this.sliderThumbRadius = 8,
    this.sliderOverlayRadius = 16,
    this.keypadButtonHeight = 60,
    this.keypadGap = 10,
    this.bottomNavHeight = 56,
    this.bottomNavMaxWidth = 320,
    this.bottomNavIndicatorWidth = 56,
    this.bottomNavIndicatorHeight = 40,
    this.sheetHandleWidth = 56,
    this.sheetHandleHeight = 4,
    this.sheetMaxHeightFactor = 0.7,
    this.chartHeight = 100,
    this.chartMinimumBodyHeight = 2,
    this.chartLoadingBaseHeightFactor = 0.8,
    this.chartLoadingHeightAmplitude = 0.2,
    this.gridLoaderSmallCell = 8,
    this.gridLoaderMediumCell = 10,
    this.gridLoaderLargeCell = 12,
    this.splashLogoWidth = 160,
    this.brandMarkSize = 48,
    this.compactFlagSize = 24,
    this.flagSize = 32,
    this.walletAvatarSize = 64,
    this.selectionIndicatorWidth = 4,
    this.selectionIndicatorHeight = 64,
  });

  final double buttonHeight;
  final double compactButtonHeight;
  final double minTouchTarget;
  final double appBarLeadingWidth;
  final double floatingNavClearance;
  final double homeHeroHeightFactor;
  final double scanFrameSizeFactor;
  final double scanFrameMaximumSize;
  final double scanHeaderExtent;
  final double recoveryWordGridAspectRatio;
  final double marketTileMinHeight;
  final double marketTextureSize;
  final double marketBadgeDotSize;
  final double sliderThumbRadius;
  final double sliderOverlayRadius;
  final double keypadButtonHeight;
  final double keypadGap;
  final double bottomNavHeight;
  final double bottomNavMaxWidth;
  final double bottomNavIndicatorWidth;
  final double bottomNavIndicatorHeight;
  final double sheetHandleWidth;
  final double sheetHandleHeight;
  final double sheetMaxHeightFactor;
  final double chartHeight;
  final double chartMinimumBodyHeight;
  final double chartLoadingBaseHeightFactor;
  final double chartLoadingHeightAmplitude;
  final double gridLoaderSmallCell;
  final double gridLoaderMediumCell;
  final double gridLoaderLargeCell;
  final double splashLogoWidth;
  final double brandMarkSize;
  final double compactFlagSize;
  final double flagSize;
  final double walletAvatarSize;
  final double selectionIndicatorWidth;
  final double selectionIndicatorHeight;

  @override
  AsterComponentMetrics copyWith({
    double? buttonHeight,
    double? compactButtonHeight,
    double? minTouchTarget,
    double? appBarLeadingWidth,
    double? floatingNavClearance,
    double? homeHeroHeightFactor,
    double? scanFrameSizeFactor,
    double? scanFrameMaximumSize,
    double? scanHeaderExtent,
    double? recoveryWordGridAspectRatio,
    double? marketTileMinHeight,
    double? marketTextureSize,
    double? marketBadgeDotSize,
    double? sliderThumbRadius,
    double? sliderOverlayRadius,
    double? keypadButtonHeight,
    double? keypadGap,
    double? bottomNavHeight,
    double? bottomNavMaxWidth,
    double? bottomNavIndicatorWidth,
    double? bottomNavIndicatorHeight,
    double? sheetHandleWidth,
    double? sheetHandleHeight,
    double? sheetMaxHeightFactor,
    double? chartHeight,
    double? chartMinimumBodyHeight,
    double? chartLoadingBaseHeightFactor,
    double? chartLoadingHeightAmplitude,
    double? gridLoaderSmallCell,
    double? gridLoaderMediumCell,
    double? gridLoaderLargeCell,
    double? splashLogoWidth,
    double? brandMarkSize,
    double? compactFlagSize,
    double? flagSize,
    double? walletAvatarSize,
    double? selectionIndicatorWidth,
    double? selectionIndicatorHeight,
  }) {
    return AsterComponentMetrics(
      buttonHeight: buttonHeight ?? this.buttonHeight,
      compactButtonHeight: compactButtonHeight ?? this.compactButtonHeight,
      minTouchTarget: minTouchTarget ?? this.minTouchTarget,
      appBarLeadingWidth: appBarLeadingWidth ?? this.appBarLeadingWidth,
      floatingNavClearance: floatingNavClearance ?? this.floatingNavClearance,
      homeHeroHeightFactor: homeHeroHeightFactor ?? this.homeHeroHeightFactor,
      scanFrameSizeFactor: scanFrameSizeFactor ?? this.scanFrameSizeFactor,
      scanFrameMaximumSize: scanFrameMaximumSize ?? this.scanFrameMaximumSize,
      scanHeaderExtent: scanHeaderExtent ?? this.scanHeaderExtent,
      recoveryWordGridAspectRatio:
          recoveryWordGridAspectRatio ?? this.recoveryWordGridAspectRatio,
      marketTileMinHeight: marketTileMinHeight ?? this.marketTileMinHeight,
      marketTextureSize: marketTextureSize ?? this.marketTextureSize,
      marketBadgeDotSize: marketBadgeDotSize ?? this.marketBadgeDotSize,
      sliderThumbRadius: sliderThumbRadius ?? this.sliderThumbRadius,
      sliderOverlayRadius: sliderOverlayRadius ?? this.sliderOverlayRadius,
      keypadButtonHeight: keypadButtonHeight ?? this.keypadButtonHeight,
      keypadGap: keypadGap ?? this.keypadGap,
      bottomNavHeight: bottomNavHeight ?? this.bottomNavHeight,
      bottomNavMaxWidth: bottomNavMaxWidth ?? this.bottomNavMaxWidth,
      bottomNavIndicatorWidth:
          bottomNavIndicatorWidth ?? this.bottomNavIndicatorWidth,
      bottomNavIndicatorHeight:
          bottomNavIndicatorHeight ?? this.bottomNavIndicatorHeight,
      sheetHandleWidth: sheetHandleWidth ?? this.sheetHandleWidth,
      sheetHandleHeight: sheetHandleHeight ?? this.sheetHandleHeight,
      sheetMaxHeightFactor: sheetMaxHeightFactor ?? this.sheetMaxHeightFactor,
      chartHeight: chartHeight ?? this.chartHeight,
      chartMinimumBodyHeight:
          chartMinimumBodyHeight ?? this.chartMinimumBodyHeight,
      chartLoadingBaseHeightFactor:
          chartLoadingBaseHeightFactor ?? this.chartLoadingBaseHeightFactor,
      chartLoadingHeightAmplitude:
          chartLoadingHeightAmplitude ?? this.chartLoadingHeightAmplitude,
      gridLoaderSmallCell: gridLoaderSmallCell ?? this.gridLoaderSmallCell,
      gridLoaderMediumCell: gridLoaderMediumCell ?? this.gridLoaderMediumCell,
      gridLoaderLargeCell: gridLoaderLargeCell ?? this.gridLoaderLargeCell,
      splashLogoWidth: splashLogoWidth ?? this.splashLogoWidth,
      brandMarkSize: brandMarkSize ?? this.brandMarkSize,
      compactFlagSize: compactFlagSize ?? this.compactFlagSize,
      flagSize: flagSize ?? this.flagSize,
      walletAvatarSize: walletAvatarSize ?? this.walletAvatarSize,
      selectionIndicatorWidth:
          selectionIndicatorWidth ?? this.selectionIndicatorWidth,
      selectionIndicatorHeight:
          selectionIndicatorHeight ?? this.selectionIndicatorHeight,
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
      minTouchTarget: _lerp(minTouchTarget, other.minTouchTarget, t),
      appBarLeadingWidth: _lerp(
        appBarLeadingWidth,
        other.appBarLeadingWidth,
        t,
      ),
      floatingNavClearance: _lerp(
        floatingNavClearance,
        other.floatingNavClearance,
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
      scanFrameMaximumSize: _lerp(
        scanFrameMaximumSize,
        other.scanFrameMaximumSize,
        t,
      ),
      scanHeaderExtent: _lerp(scanHeaderExtent, other.scanHeaderExtent, t),
      recoveryWordGridAspectRatio: _lerp(
        recoveryWordGridAspectRatio,
        other.recoveryWordGridAspectRatio,
        t,
      ),
      marketTileMinHeight: _lerp(
        marketTileMinHeight,
        other.marketTileMinHeight,
        t,
      ),
      marketTextureSize: _lerp(marketTextureSize, other.marketTextureSize, t),
      marketBadgeDotSize: _lerp(
        marketBadgeDotSize,
        other.marketBadgeDotSize,
        t,
      ),
      sliderThumbRadius: _lerp(sliderThumbRadius, other.sliderThumbRadius, t),
      sliderOverlayRadius: _lerp(
        sliderOverlayRadius,
        other.sliderOverlayRadius,
        t,
      ),
      keypadButtonHeight: _lerp(
        keypadButtonHeight,
        other.keypadButtonHeight,
        t,
      ),
      keypadGap: _lerp(keypadGap, other.keypadGap, t),
      bottomNavHeight: _lerp(bottomNavHeight, other.bottomNavHeight, t),
      bottomNavMaxWidth: _lerp(bottomNavMaxWidth, other.bottomNavMaxWidth, t),
      bottomNavIndicatorWidth: _lerp(
        bottomNavIndicatorWidth,
        other.bottomNavIndicatorWidth,
        t,
      ),
      bottomNavIndicatorHeight: _lerp(
        bottomNavIndicatorHeight,
        other.bottomNavIndicatorHeight,
        t,
      ),
      sheetHandleWidth: _lerp(sheetHandleWidth, other.sheetHandleWidth, t),
      sheetHandleHeight: _lerp(sheetHandleHeight, other.sheetHandleHeight, t),
      sheetMaxHeightFactor: _lerp(
        sheetMaxHeightFactor,
        other.sheetMaxHeightFactor,
        t,
      ),
      chartHeight: _lerp(chartHeight, other.chartHeight, t),
      chartMinimumBodyHeight: _lerp(
        chartMinimumBodyHeight,
        other.chartMinimumBodyHeight,
        t,
      ),
      chartLoadingBaseHeightFactor: _lerp(
        chartLoadingBaseHeightFactor,
        other.chartLoadingBaseHeightFactor,
        t,
      ),
      chartLoadingHeightAmplitude: _lerp(
        chartLoadingHeightAmplitude,
        other.chartLoadingHeightAmplitude,
        t,
      ),
      gridLoaderSmallCell: _lerp(
        gridLoaderSmallCell,
        other.gridLoaderSmallCell,
        t,
      ),
      gridLoaderMediumCell: _lerp(
        gridLoaderMediumCell,
        other.gridLoaderMediumCell,
        t,
      ),
      gridLoaderLargeCell: _lerp(
        gridLoaderLargeCell,
        other.gridLoaderLargeCell,
        t,
      ),
      splashLogoWidth: _lerp(splashLogoWidth, other.splashLogoWidth, t),
      brandMarkSize: _lerp(brandMarkSize, other.brandMarkSize, t),
      compactFlagSize: _lerp(compactFlagSize, other.compactFlagSize, t),
      flagSize: _lerp(flagSize, other.flagSize, t),
      walletAvatarSize: _lerp(walletAvatarSize, other.walletAvatarSize, t),
      selectionIndicatorWidth: _lerp(
        selectionIndicatorWidth,
        other.selectionIndicatorWidth,
        t,
      ),
      selectionIndicatorHeight: _lerp(
        selectionIndicatorHeight,
        other.selectionIndicatorHeight,
        t,
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

import 'package:flutter/material.dart';

class _AsterPalette {
  const _AsterPalette._();

  static const ink = Color(0xFF1D2129);
  static const blueBase = Color(0xFF165DFF);
  static const blue900 = Color(0xFF0E42D2);
  static const blue800 = Color(0xFF4080FF);
  static const blue600 = Color(0xFF6AA1FF);
  static const blue500 = Color(0xFF94BFFF);
  static const blue300 = Color(0xFFBEDAFF);
  static const blue200 = Color(0xFFE8F3FF);
  static const surface = Color(0xFFFFFFFF);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const transparent = Color(0x00000000);
  static const neutral50 = Color(0xFFF7F8FA);
  static const neutral100 = Color(0xFFF2F3F5);
  static const neutral200 = Color(0xFFE5E6EB);
  static const neutral300 = Color(0xFFC9CDD4);
  static const neutral500 = Color(0xFF86909C);
  static const neutral700 = Color(0xFF4E5969);
  static const meshDeep = Color(0xFF000C79);
  static const meshMain = Color(0xFF001AFF);
  static const meshBright = Color(0xFF007BFF);
  static const meshSoft = Color(0xFF8BD0FF);
  static const success = Color(0xFF00B42A);
  static const successContainer = Color(0xFFE8F8E5);
  static const warning = Color(0xFFFF7D00);
  static const warningContainer = Color(0xFFFFF7E8);
  static const danger = Color(0xFFF53F3F);
  static const dangerContainer = Color(0xFFFFECE8);
  static const bitcoin = Color(0xFFF7931A);
  static const liquid = Color(0xFF14A38B);
}

/// App-specific color roles that are not covered by Material [ColorScheme].
///
/// Material components should use [ColorScheme]. Product UI that needs
/// financial/status/brand-art meaning should use this extension.
@immutable
class AsterColors extends ThemeExtension<AsterColors> {
  const AsterColors({
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.surfaceRaised,
    required this.surfaceSubtle,
    required this.borderSubtle,
    required this.overlay,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.bitcoin,
    required this.liquid,
    required this.chartPositive,
    required this.chartNegative,
    required this.onBrandArt,
    required this.transparentSurface,
    required this.artNoiseTint,
    required this.scanOverlayBase,
    required this.scanControlSurface,
    required this.onScan,
    required this.onMarketTile,
    required this.brandArtDark,
    required this.brandArtDeep,
    required this.brandArtMain,
    required this.brandArtBright,
    required this.brandArtSoft,
  });

  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color surfaceRaised;
  final Color surfaceSubtle;
  final Color borderSubtle;
  final Color overlay;
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color bitcoin;
  final Color liquid;
  final Color chartPositive;
  final Color chartNegative;
  final Color onBrandArt;
  final Color transparentSurface;
  final Color artNoiseTint;
  final Color scanOverlayBase;
  final Color scanControlSurface;
  final Color onScan;
  final Color onMarketTile;
  final Color brandArtDark;
  final Color brandArtDeep;
  final Color brandArtMain;
  final Color brandArtBright;
  final Color brandArtSoft;

  static const light = AsterColors(
    textSecondary: _AsterPalette.neutral700,
    textTertiary: _AsterPalette.neutral500,
    textDisabled: _AsterPalette.neutral300,
    surfaceRaised: _AsterPalette.white,
    surfaceSubtle: _AsterPalette.neutral100,
    borderSubtle: _AsterPalette.neutral200,
    overlay: Color(0x991D2129),
    success: _AsterPalette.success,
    onSuccess: _AsterPalette.white,
    successContainer: _AsterPalette.successContainer,
    warning: _AsterPalette.warning,
    onWarning: _AsterPalette.ink,
    warningContainer: _AsterPalette.warningContainer,
    danger: _AsterPalette.danger,
    onDanger: _AsterPalette.white,
    dangerContainer: _AsterPalette.dangerContainer,
    bitcoin: _AsterPalette.bitcoin,
    liquid: _AsterPalette.liquid,
    chartPositive: _AsterPalette.success,
    chartNegative: _AsterPalette.danger,
    onBrandArt: _AsterPalette.white,
    transparentSurface: _AsterPalette.transparent,
    artNoiseTint: _AsterPalette.black,
    scanOverlayBase: _AsterPalette.black,
    scanControlSurface: _AsterPalette.black,
    onScan: _AsterPalette.white,
    onMarketTile: _AsterPalette.white,
    brandArtDark: _AsterPalette.black,
    brandArtDeep: _AsterPalette.meshDeep,
    brandArtMain: _AsterPalette.meshMain,
    brandArtBright: _AsterPalette.meshBright,
    brandArtSoft: _AsterPalette.meshSoft,
  );

  static ColorScheme lightColorScheme() {
    return const ColorScheme.light(
      primary: _AsterPalette.blueBase,
      onPrimary: _AsterPalette.white,
      primaryContainer: _AsterPalette.blue200,
      onPrimaryContainer: _AsterPalette.blue900,
      secondary: _AsterPalette.blue600,
      onSecondary: _AsterPalette.white,
      secondaryContainer: _AsterPalette.blue300,
      onSecondaryContainer: _AsterPalette.blue900,
      tertiary: _AsterPalette.blue800,
      onTertiary: _AsterPalette.white,
      tertiaryContainer: _AsterPalette.blue500,
      onTertiaryContainer: _AsterPalette.blue900,
      error: _AsterPalette.danger,
      onError: _AsterPalette.white,
      errorContainer: _AsterPalette.dangerContainer,
      onErrorContainer: _AsterPalette.ink,
      surface: _AsterPalette.surface,
      onSurface: _AsterPalette.ink,
      surfaceContainerLowest: _AsterPalette.white,
      surfaceContainerLow: _AsterPalette.neutral50,
      surfaceContainer: _AsterPalette.neutral100,
      surfaceContainerHigh: _AsterPalette.neutral200,
      surfaceContainerHighest: _AsterPalette.neutral300,
      onSurfaceVariant: _AsterPalette.neutral500,
      outline: _AsterPalette.neutral200,
      outlineVariant: _AsterPalette.neutral100,
      inverseSurface: _AsterPalette.ink,
      onInverseSurface: _AsterPalette.white,
      inversePrimary: _AsterPalette.blue600,
      shadow: _AsterPalette.ink,
      scrim: _AsterPalette.ink,
    );
  }

  @override
  AsterColors copyWith({
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? surfaceRaised,
    Color? surfaceSubtle,
    Color? borderSubtle,
    Color? overlay,
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? bitcoin,
    Color? liquid,
    Color? chartPositive,
    Color? chartNegative,
    Color? onBrandArt,
    Color? transparentSurface,
    Color? artNoiseTint,
    Color? scanOverlayBase,
    Color? scanControlSurface,
    Color? onScan,
    Color? onMarketTile,
    Color? brandArtDark,
    Color? brandArtDeep,
    Color? brandArtMain,
    Color? brandArtBright,
    Color? brandArtSoft,
  }) {
    return AsterColors(
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      overlay: overlay ?? this.overlay,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      bitcoin: bitcoin ?? this.bitcoin,
      liquid: liquid ?? this.liquid,
      chartPositive: chartPositive ?? this.chartPositive,
      chartNegative: chartNegative ?? this.chartNegative,
      onBrandArt: onBrandArt ?? this.onBrandArt,
      transparentSurface: transparentSurface ?? this.transparentSurface,
      artNoiseTint: artNoiseTint ?? this.artNoiseTint,
      scanOverlayBase: scanOverlayBase ?? this.scanOverlayBase,
      scanControlSurface: scanControlSurface ?? this.scanControlSurface,
      onScan: onScan ?? this.onScan,
      onMarketTile: onMarketTile ?? this.onMarketTile,
      brandArtDark: brandArtDark ?? this.brandArtDark,
      brandArtDeep: brandArtDeep ?? this.brandArtDeep,
      brandArtMain: brandArtMain ?? this.brandArtMain,
      brandArtBright: brandArtBright ?? this.brandArtBright,
      brandArtSoft: brandArtSoft ?? this.brandArtSoft,
    );
  }

  @override
  AsterColors lerp(ThemeExtension<AsterColors>? other, double t) {
    if (other is! AsterColors) return this;
    return AsterColors(
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      bitcoin: Color.lerp(bitcoin, other.bitcoin, t)!,
      liquid: Color.lerp(liquid, other.liquid, t)!,
      chartPositive: Color.lerp(chartPositive, other.chartPositive, t)!,
      chartNegative: Color.lerp(chartNegative, other.chartNegative, t)!,
      onBrandArt: Color.lerp(onBrandArt, other.onBrandArt, t)!,
      transparentSurface: Color.lerp(
        transparentSurface,
        other.transparentSurface,
        t,
      )!,
      artNoiseTint: Color.lerp(artNoiseTint, other.artNoiseTint, t)!,
      scanOverlayBase: Color.lerp(scanOverlayBase, other.scanOverlayBase, t)!,
      scanControlSurface: Color.lerp(
        scanControlSurface,
        other.scanControlSurface,
        t,
      )!,
      onScan: Color.lerp(onScan, other.onScan, t)!,
      onMarketTile: Color.lerp(onMarketTile, other.onMarketTile, t)!,
      brandArtDark: Color.lerp(brandArtDark, other.brandArtDark, t)!,
      brandArtDeep: Color.lerp(brandArtDeep, other.brandArtDeep, t)!,
      brandArtMain: Color.lerp(brandArtMain, other.brandArtMain, t)!,
      brandArtBright: Color.lerp(brandArtBright, other.brandArtBright, t)!,
      brandArtSoft: Color.lerp(brandArtSoft, other.brandArtSoft, t)!,
    );
  }
}

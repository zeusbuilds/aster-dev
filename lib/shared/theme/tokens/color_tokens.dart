import 'package:flutter/material.dart';

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
    required this.marketBuyGradient,
    required this.marketSellGradient,
    required this.marketSwapGradient,
    required this.marketLendGradient,
    required this.marketSendGradient,
    required this.marketReceiveGradient,
    required this.homeGradient,
    required this.splashGradient,
  });

  static const ink = Color(0xFF1D2129);
  static const blueBase = Color(0xFF165DFF);
  static const blue900 = Color(0xFF0E42D2);
  static const blue800 = Color(0xFF4080FF);
  static const blue600 = Color(0xFF6AA1FF);
  static const blue500 = Color(0xFF94BFFF);
  static const blue300 = Color(0xFFBEDAFF);
  static const blue200 = Color(0xFFE8F3FF);
  static const blue100 = Color(0xFFE8F3FF);
  static const surface = Color(0xFFFFFFFF);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const transparent = Color(0x00000000);
  static const meshDeep = Color(0xFF000C79);
  static const meshMain = Color(0xFF001AFF);
  static const meshBright = Color(0xFF007BFF);
  static const meshSoft = Color(0xFF8BD0FF);
  static const splashTop = Color(0xFF8BD6FF);

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
  final List<Color> marketBuyGradient;
  final List<Color> marketSellGradient;
  final List<Color> marketSwapGradient;
  final List<Color> marketLendGradient;
  final List<Color> marketSendGradient;
  final List<Color> marketReceiveGradient;
  final List<Color> homeGradient;
  final List<Color> splashGradient;

  static const light = AsterColors(
    textSecondary: Color(0xFF4E5969),
    textTertiary: Color(0xFF86909C),
    textDisabled: Color(0xFFC9CDD4),
    surfaceRaised: white,
    surfaceSubtle: Color(0xFFF2F3F5),
    borderSubtle: Color(0xFFE5E6EB),
    overlay: Color(0x991D2129),
    success: Color(0xFF00B42A),
    onSuccess: white,
    successContainer: Color(0xFFE8F8E5),
    warning: Color(0xFFFF7D00),
    onWarning: ink,
    warningContainer: Color(0xFFFFF7E8),
    danger: Color(0xFFF53F3F),
    onDanger: white,
    dangerContainer: Color(0xFFFFECE8),
    bitcoin: Color(0xFFF7931A),
    liquid: Color(0xFF14A38B),
    chartPositive: Color(0xFF00B42A),
    chartNegative: Color(0xFFF53F3F),
    onBrandArt: white,
    transparentSurface: transparent,
    artNoiseTint: black,
    scanOverlayBase: black,
    scanControlSurface: black,
    onScan: white,
    onMarketTile: white,
    brandArtDark: black,
    brandArtDeep: meshDeep,
    brandArtMain: meshMain,
    brandArtBright: meshBright,
    brandArtSoft: meshSoft,
    marketBuyGradient: [Color(0xFFE89B6B), Color(0xFFD47A4A)],
    marketSellGradient: [Color(0xFF6BA8E8), Color(0xFF4A88C8)],
    marketSwapGradient: [Color(0xFF696969), Color(0xFF696969)],
    marketLendGradient: [Color(0xFF7B8FA8), Color(0xFF5A6B82)],
    marketSendGradient: [Color(0xFF9B7BB8), Color(0xFF7A5A96)],
    marketReceiveGradient: [Color(0xFF5BB89A), Color(0xFF3D9678)],
    homeGradient: [black, meshDeep, meshMain, meshBright, meshSoft],
    splashGradient: [splashTop, meshMain, black],
  );

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
    List<Color>? marketBuyGradient,
    List<Color>? marketSellGradient,
    List<Color>? marketSwapGradient,
    List<Color>? marketLendGradient,
    List<Color>? marketSendGradient,
    List<Color>? marketReceiveGradient,
    List<Color>? homeGradient,
    List<Color>? splashGradient,
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
      marketBuyGradient: marketBuyGradient ?? this.marketBuyGradient,
      marketSellGradient: marketSellGradient ?? this.marketSellGradient,
      marketSwapGradient: marketSwapGradient ?? this.marketSwapGradient,
      marketLendGradient: marketLendGradient ?? this.marketLendGradient,
      marketSendGradient: marketSendGradient ?? this.marketSendGradient,
      marketReceiveGradient:
          marketReceiveGradient ?? this.marketReceiveGradient,
      homeGradient: homeGradient ?? this.homeGradient,
      splashGradient: splashGradient ?? this.splashGradient,
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
      marketBuyGradient: _lerpColorList(
        marketBuyGradient,
        other.marketBuyGradient,
        t,
      ),
      marketSellGradient: _lerpColorList(
        marketSellGradient,
        other.marketSellGradient,
        t,
      ),
      marketSwapGradient: _lerpColorList(
        marketSwapGradient,
        other.marketSwapGradient,
        t,
      ),
      marketLendGradient: _lerpColorList(
        marketLendGradient,
        other.marketLendGradient,
        t,
      ),
      marketSendGradient: _lerpColorList(
        marketSendGradient,
        other.marketSendGradient,
        t,
      ),
      marketReceiveGradient: _lerpColorList(
        marketReceiveGradient,
        other.marketReceiveGradient,
        t,
      ),
      homeGradient: _lerpColorList(homeGradient, other.homeGradient, t),
      splashGradient: _lerpColorList(splashGradient, other.splashGradient, t),
    );
  }

  static List<Color> _lerpColorList(List<Color> a, List<Color> b, double t) {
    final length = a.length < b.length ? a.length : b.length;
    return List<Color>.generate(length, (i) => Color.lerp(a[i], b[i], t)!);
  }
}

import 'package:flutter/material.dart';

@immutable
class AsterGradientSpec {
  const AsterGradientSpec({
    required this.colors,
    this.stops,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  final List<Color> colors;
  final List<double>? stops;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  LinearGradient toLinearGradient() {
    return LinearGradient(colors: colors, stops: stops, begin: begin, end: end);
  }

  AsterGradientSpec copyWith({
    List<Color>? colors,
    List<double>? stops,
    AlignmentGeometry? begin,
    AlignmentGeometry? end,
  }) {
    return AsterGradientSpec(
      colors: colors ?? this.colors,
      stops: stops ?? this.stops,
      begin: begin ?? this.begin,
      end: end ?? this.end,
    );
  }

  AsterGradientSpec lerp(AsterGradientSpec other, double t) {
    return AsterGradientSpec(
      colors: _lerpColorList(colors, other.colors, t),
      stops: stops ?? other.stops,
      begin: t < 0.5 ? begin : other.begin,
      end: t < 0.5 ? end : other.end,
    );
  }

  static List<Color> _lerpColorList(List<Color> a, List<Color> b, double t) {
    final length = a.length < b.length ? a.length : b.length;
    return List<Color>.generate(length, (i) => Color.lerp(a[i], b[i], t)!);
  }
}

/// Authored gradient recipes.
@immutable
class AsterGradients extends ThemeExtension<AsterGradients> {
  const AsterGradients({
    required this.marketBuy,
    required this.marketSell,
    required this.marketSwap,
    required this.marketLend,
    required this.marketSend,
    required this.marketReceive,
    required this.splashBackdrop,
  });

  final AsterGradientSpec marketBuy;
  final AsterGradientSpec marketSell;
  final AsterGradientSpec marketSwap;
  final AsterGradientSpec marketLend;
  final AsterGradientSpec marketSend;
  final AsterGradientSpec marketReceive;
  final AsterGradientSpec splashBackdrop;

  static const light = AsterGradients(
    marketBuy: AsterGradientSpec(
      colors: [Color(0xFFE89B6B), Color(0xFFD47A4A)],
    ),
    marketSell: AsterGradientSpec(
      colors: [Color(0xFF6BA8E8), Color(0xFF4A88C8)],
    ),
    marketSwap: AsterGradientSpec(
      colors: [Color(0xFF696969), Color(0xFF696969)],
    ),
    marketLend: AsterGradientSpec(
      colors: [Color(0xFF7B8FA8), Color(0xFF5A6B82)],
    ),
    marketSend: AsterGradientSpec(
      colors: [Color(0xFF9B7BB8), Color(0xFF7A5A96)],
    ),
    marketReceive: AsterGradientSpec(
      colors: [Color(0xFF5BB89A), Color(0xFF3D9678)],
    ),
    splashBackdrop: AsterGradientSpec(
      colors: [Color(0xFF8BD6FF), Color(0xFF001AFF), Color(0xFF000000)],
      stops: [0, 0.5, 1],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
  );

  @override
  AsterGradients copyWith({
    AsterGradientSpec? marketBuy,
    AsterGradientSpec? marketSell,
    AsterGradientSpec? marketSwap,
    AsterGradientSpec? marketLend,
    AsterGradientSpec? marketSend,
    AsterGradientSpec? marketReceive,
    AsterGradientSpec? splashBackdrop,
  }) {
    return AsterGradients(
      marketBuy: marketBuy ?? this.marketBuy,
      marketSell: marketSell ?? this.marketSell,
      marketSwap: marketSwap ?? this.marketSwap,
      marketLend: marketLend ?? this.marketLend,
      marketSend: marketSend ?? this.marketSend,
      marketReceive: marketReceive ?? this.marketReceive,
      splashBackdrop: splashBackdrop ?? this.splashBackdrop,
    );
  }

  @override
  AsterGradients lerp(ThemeExtension<AsterGradients>? other, double t) {
    if (other is! AsterGradients) return this;
    return AsterGradients(
      marketBuy: marketBuy.lerp(other.marketBuy, t),
      marketSell: marketSell.lerp(other.marketSell, t),
      marketSwap: marketSwap.lerp(other.marketSwap, t),
      marketLend: marketLend.lerp(other.marketLend, t),
      marketSend: marketSend.lerp(other.marketSend, t),
      marketReceive: marketReceive.lerp(other.marketReceive, t),
      splashBackdrop: splashBackdrop.lerp(other.splashBackdrop, t),
    );
  }
}

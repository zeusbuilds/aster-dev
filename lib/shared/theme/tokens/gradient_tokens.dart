import 'package:flutter/material.dart';

@immutable
class AsterGradientSpec {
  AsterGradientSpec({
    required List<Color> colors,
    List<double>? stops,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  }) : colors = _validateColors(colors),
       stops = _validateStops(colors, stops);

  final List<Color> colors;
  final List<double>? stops;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  static List<Color> _validateColors(List<Color> colors) {
    if (colors.length < 2) {
      throw ArgumentError.value(
        colors,
        'colors',
        'A gradient requires at least two colors.',
      );
    }
    return List<Color>.unmodifiable(colors);
  }

  static List<double>? _validateStops(List<Color> colors, List<double>? stops) {
    if (stops == null) return null;
    if (stops.length != colors.length) {
      throw ArgumentError.value(
        stops,
        'stops',
        'Gradient stops must match the number of colors.',
      );
    }
    var previous = -1.0;
    for (final stop in stops) {
      if (!stop.isFinite || stop < 0 || stop > 1 || stop < previous) {
        throw ArgumentError.value(
          stops,
          'stops',
          'Gradient stops must be finite, ordered values from 0 to 1.',
        );
      }
      previous = stop;
    }
    return List<double>.unmodifiable(stops);
  }

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
    final gradient = LinearGradient.lerp(
      toLinearGradient(),
      other.toLinearGradient(),
      t,
    )!;
    return AsterGradientSpec(
      colors: gradient.colors,
      stops: gradient.stops,
      begin: gradient.begin,
      end: gradient.end,
    );
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
    required this.scanOverlay,
  });

  final AsterGradientSpec marketBuy;
  final AsterGradientSpec marketSell;
  final AsterGradientSpec marketSwap;
  final AsterGradientSpec marketLend;
  final AsterGradientSpec marketSend;
  final AsterGradientSpec marketReceive;
  final AsterGradientSpec splashBackdrop;
  final AsterGradientSpec scanOverlay;

  static final light = AsterGradients(
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
    scanOverlay: AsterGradientSpec(
      colors: [Color(0xFF000000), Color(0xBF000000), Color(0xA6000000)],
      stops: [0.25, 0.5, 1],
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
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
    AsterGradientSpec? scanOverlay,
  }) {
    return AsterGradients(
      marketBuy: marketBuy ?? this.marketBuy,
      marketSell: marketSell ?? this.marketSell,
      marketSwap: marketSwap ?? this.marketSwap,
      marketLend: marketLend ?? this.marketLend,
      marketSend: marketSend ?? this.marketSend,
      marketReceive: marketReceive ?? this.marketReceive,
      splashBackdrop: splashBackdrop ?? this.splashBackdrop,
      scanOverlay: scanOverlay ?? this.scanOverlay,
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
      scanOverlay: scanOverlay.lerp(other.scanOverlay, t),
    );
  }
}

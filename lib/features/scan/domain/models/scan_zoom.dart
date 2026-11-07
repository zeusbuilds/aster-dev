import 'package:flutter/foundation.dart';

/// Confirmed camera magnification and hardware bounds, relative to its lens.
///
/// This is deliberately independent of a plugin's normalized zoom slider.
/// Unknown capabilities are represented by null rather than an invented 1×.
@immutable
final class ScanZoomRange {
  const ScanZoomRange({
    required this.minimum,
    required this.maximum,
    required this.current,
  });

  final double minimum;
  final double maximum;
  final double current;

  bool get isValid =>
      minimum.isFinite &&
      maximum.isFinite &&
      current.isFinite &&
      minimum > 0 &&
      current > 0 &&
      maximum >= minimum &&
      current >= minimum - _nativePrecisionTolerance &&
      current <= maximum + _nativePrecisionTolerance;

  /// Familiar magnifications that this camera actually supports.
  ///
  /// A constrained camera may top out between presets (for example 1.5×).
  /// Include that endpoint so its available zoom remains useful and truthful.
  /// Higher-capacity cameras still cycle only through 1×, 2× and 3×.
  List<double> get presets {
    if (!isValid) return const [];
    final values = <double>[
      if (minimum > 1 || maximum < 1) minimum,
      for (final ratio in const [1.0, 2.0, 3.0])
        if (ratio >= minimum && ratio <= maximum) ratio,
      if (maximum < 3) maximum,
    ]..sort();
    final unique = <double>[];
    for (final value in values) {
      if (unique.isEmpty || (unique.last - value).abs() > _tolerance) {
        unique.add(value);
      }
    }
    return List.unmodifiable(unique);
  }

  bool get canChange =>
      isValid && maximum - minimum > _tolerance && presets.length > 1;

  double get nextRatio {
    final values = presets;
    if (values.isEmpty) return current;
    return values.firstWhere(
      (value) => value > current + _tolerance,
      orElse: () => values.first,
    );
  }

  String get displayLabel => '${_format(current)}x';
  String get semanticLabel => 'Zoom ${_format(current)} times';

  static String _format(double ratio) {
    // Hardware uses floats. Avoid displaying 1.9999999× for the 2× preset.
    return ratio
        .toStringAsFixed(ratio < 0.01 ? 4 : 2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  bool operator ==(Object other) =>
      other is ScanZoomRange &&
      other.minimum == minimum &&
      other.maximum == maximum &&
      other.current == current;

  @override
  int get hashCode => Object.hash(minimum, maximum, current);
}

const _tolerance = 0.01;
const _nativePrecisionTolerance = 0.0001;

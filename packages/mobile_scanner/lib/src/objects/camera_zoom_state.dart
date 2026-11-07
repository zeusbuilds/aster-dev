import 'package:flutter/foundation.dart';

/// Camera-reported zoom magnification, relative to the standard 1× camera.
///
/// These are actual ratios, unlike the legacy normalized `zoomScale` slider.
/// A fixed-zoom camera may report identical minimum and maximum ratios.
@immutable
final class CameraZoomState {
  /// Creates a zoom snapshot, rejecting invalid or inconsistent native data.
  factory CameraZoomState({
    required double minZoomRatio,
    required double maxZoomRatio,
    required double zoomRatio,
  }) {
    if (!minZoomRatio.isFinite ||
        !maxZoomRatio.isFinite ||
        !zoomRatio.isFinite ||
        minZoomRatio <= 0 ||
        maxZoomRatio < minZoomRatio ||
        zoomRatio < minZoomRatio - 0.0001 ||
        zoomRatio > maxZoomRatio + 0.0001) {
      throw const FormatException('Camera returned invalid zoom capabilities.');
    }
    return CameraZoomState._(minZoomRatio, maxZoomRatio, zoomRatio);
  }

  const CameraZoomState._(
    this.minZoomRatio,
    this.maxZoomRatio,
    this.zoomRatio,
  );

  /// Parses a native result without inventing missing capabilities.
  factory CameraZoomState.fromNative(Map<Object?, Object?>? data) {
    final minimum = data?['minZoomRatio'];
    final maximum = data?['maxZoomRatio'];
    final current = data?['zoomRatio'];
    if (minimum is! num || maximum is! num || current is! num) {
      throw const FormatException('Camera did not report zoom capabilities.');
    }
    return CameraZoomState(
      minZoomRatio: minimum.toDouble(),
      maxZoomRatio: maximum.toDouble(),
      zoomRatio: current.toDouble(),
    );
  }

  /// Smallest magnification supported by the running camera configuration.
  final double minZoomRatio;

  /// Largest magnification supported by the running camera configuration.
  final double maxZoomRatio;

  /// Magnification actually reported after applying the zoom request.
  final double zoomRatio;
}

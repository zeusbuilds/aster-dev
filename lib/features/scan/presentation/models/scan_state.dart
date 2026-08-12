import 'package:flutter/foundation.dart';

import '../../../../core/errors/errors.dart';
import '../../data/services/services.dart';

/// User-initiated operations that temporarily disable Scan controls.
enum ScanOperation {
  togglingTorch,
  changingZoom,
  selectingGallery,
  restarting,
  pausingForNavigation,
}

/// App-owned normalized zoom presets.
///
/// `mobile_scanner` exposes a normalized 0...1 scale rather than physical lens
/// magnification. Labels therefore describe relative levels and never claim a
/// device-specific optical multiplier.
enum ScanZoomPreset {
  normal(scale: 0, displayLabel: '1/3'),
  closer(scale: 0.5, displayLabel: '2/3'),
  closest(scale: 1, displayLabel: '3/3');

  const ScanZoomPreset({required this.scale, required this.displayLabel});

  final double scale;
  final String displayLabel;

  String get semanticLabel =>
      'Zoom level ${index + 1} of ${ScanZoomPreset.values.length}';

  ScanZoomPreset get next =>
      ScanZoomPreset.values[(index + 1) % ScanZoomPreset.values.length];

  static ScanZoomPreset nearest(double scale) {
    if (!scale.isFinite) return ScanZoomPreset.normal;
    return ScanZoomPreset.values.reduce((closest, candidate) {
      final closestDistance = (closest.scale - scale).abs();
      final candidateDistance = (candidate.scale - scale).abs();
      return candidateDistance < closestDistance ? candidate : closest;
    });
  }
}

/// Immutable presentation state for one isolated Scan purpose.
@immutable
final class ScanState {
  const ScanState({
    this.cameraInitialized = false,
    this.cameraRunning = false,
    this.torchAvailable = false,
    this.flashOn = false,
    this.zoomPreset = ScanZoomPreset.normal,
    this.captureLocked = false,
    this.operation,
    this.failure,
  });

  factory ScanState.fromSession(ScanSessionSnapshot snapshot) {
    return ScanState(
      cameraInitialized: snapshot.isInitialized,
      cameraRunning: snapshot.isRunning,
      torchAvailable: snapshot.torchAvailable,
      flashOn: snapshot.torchOn,
      zoomPreset: ScanZoomPreset.nearest(snapshot.zoomScale),
      captureLocked: snapshot.captureLocked,
      failure: snapshot.failure,
    );
  }

  final bool cameraInitialized;
  final bool cameraRunning;
  final bool torchAvailable;
  final bool flashOn;
  final ScanZoomPreset zoomPreset;
  final bool captureLocked;
  final ScanOperation? operation;
  final AppFailure? failure;

  bool get cameraReady => cameraInitialized && cameraRunning && failure == null;
  bool get isBusy => operation != null;
  bool get galleryBusy => operation == ScanOperation.selectingGallery;
  bool get hasCommittedCapture => captureLocked && failure == null;
  bool get canUseGallery => !isBusy && !hasCommittedCapture;
  bool get canEnterManually => !isBusy && !hasCommittedCapture;
  bool get canToggleFlash =>
      cameraReady && torchAvailable && !isBusy && !captureLocked;
  bool get canChangeZoom => cameraReady && !isBusy && !captureLocked;
  bool get canRetry => failure?.retryable ?? false;

  ScanState copyWith({
    bool? cameraInitialized,
    bool? cameraRunning,
    bool? torchAvailable,
    bool? flashOn,
    ScanZoomPreset? zoomPreset,
    bool? captureLocked,
    Object? operation = _unset,
    Object? failure = _unset,
  }) {
    return ScanState(
      cameraInitialized: cameraInitialized ?? this.cameraInitialized,
      cameraRunning: cameraRunning ?? this.cameraRunning,
      torchAvailable: torchAvailable ?? this.torchAvailable,
      flashOn: flashOn ?? this.flashOn,
      zoomPreset: zoomPreset ?? this.zoomPreset,
      captureLocked: captureLocked ?? this.captureLocked,
      operation: identical(operation, _unset)
          ? this.operation
          : operation as ScanOperation?,
      failure: identical(failure, _unset)
          ? this.failure
          : failure as AppFailure?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScanState &&
      other.cameraInitialized == cameraInitialized &&
      other.cameraRunning == cameraRunning &&
      other.torchAvailable == torchAvailable &&
      other.flashOn == flashOn &&
      other.zoomPreset == zoomPreset &&
      other.captureLocked == captureLocked &&
      other.operation == operation &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(
    cameraInitialized,
    cameraRunning,
    torchAvailable,
    flashOn,
    zoomPreset,
    captureLocked,
    operation,
    failure,
  );
}

const _unset = Object();

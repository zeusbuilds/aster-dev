import 'package:flutter/foundation.dart';

import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';

/// User-initiated operations that temporarily disable Scan controls.
enum ScanOperation {
  togglingTorch,
  changingZoom,
  selectingGallery,
  pausingForNavigation,
}

/// Immutable presentation state for one isolated Scan purpose.
@immutable
final class ScanState {
  const ScanState({
    this.cameraInitialized = false,
    this.cameraRunning = false,
    this.torchAvailable = false,
    this.flashOn = false,
    this.zoom,
    this.captureLocked = false,
    this.galleryPhase = ScanGalleryPhase.idle,
    this.operation,
    this.failure,
  });

  final bool cameraInitialized;
  final bool cameraRunning;
  final bool torchAvailable;
  final bool flashOn;
  final ScanZoomRange? zoom;
  final bool captureLocked;
  final ScanGalleryPhase galleryPhase;
  final ScanOperation? operation;
  final AppFailure? failure;

  bool get cameraReady => cameraInitialized && cameraRunning && failure == null;
  bool get isBusy => operation != null;
  bool get galleryBusy => operation == ScanOperation.selectingGallery;
  bool get galleryAnalyzing => galleryPhase == ScanGalleryPhase.analyzing;
  bool get hasCommittedCapture => captureLocked && failure == null;
  bool get canUseGallery => !isBusy && !hasCommittedCapture;
  bool get canEnterManually => !isBusy && !hasCommittedCapture;
  bool get canToggleFlash =>
      cameraReady && torchAvailable && !isBusy && !captureLocked;
  bool get canChangeZoom =>
      cameraReady && (zoom?.canChange ?? false) && !isBusy && !captureLocked;

  ScanState copyWith({
    bool? cameraInitialized,
    bool? cameraRunning,
    bool? torchAvailable,
    bool? flashOn,
    Object? zoom = _unset,
    bool? captureLocked,
    ScanGalleryPhase? galleryPhase,
    Object? operation = _unset,
    Object? failure = _unset,
  }) {
    return ScanState(
      cameraInitialized: cameraInitialized ?? this.cameraInitialized,
      cameraRunning: cameraRunning ?? this.cameraRunning,
      torchAvailable: torchAvailable ?? this.torchAvailable,
      flashOn: flashOn ?? this.flashOn,
      zoom: identical(zoom, _unset) ? this.zoom : zoom as ScanZoomRange?,
      captureLocked: captureLocked ?? this.captureLocked,
      galleryPhase: galleryPhase ?? this.galleryPhase,
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
      other.zoom == zoom &&
      other.captureLocked == captureLocked &&
      other.galleryPhase == galleryPhase &&
      other.operation == operation &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(
    cameraInitialized,
    cameraRunning,
    torchAvailable,
    flashOn,
    zoom,
    captureLocked,
    galleryPhase,
    operation,
    failure,
  );
}

const _unset = Object();

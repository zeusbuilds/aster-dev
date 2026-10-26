import 'package:flutter/material.dart';

import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';

/// Immutable platform-camera state exposed to app presentation.
@immutable
final class ScanSessionSnapshot {
  const ScanSessionSnapshot({
    this.isInitialized = false,
    this.isRunning = false,
    this.torchAvailable = false,
    this.torchOn = false,
    this.zoomScale = 0,
    this.captureLocked = false,
    this.galleryPhase = ScanGalleryPhase.idle,
    this.failure,
  });

  final bool isInitialized;
  final bool isRunning;
  final bool torchAvailable;
  final bool torchOn;
  final double zoomScale;
  final bool captureLocked;
  final ScanGalleryPhase galleryPhase;
  final AppFailure? failure;

  bool get isReady => isInitialized && isRunning && failure == null;

  ScanSessionSnapshot copyWith({
    bool? isInitialized,
    bool? isRunning,
    bool? torchAvailable,
    bool? torchOn,
    double? zoomScale,
    bool? captureLocked,
    ScanGalleryPhase? galleryPhase,
    Object? failure = _unset,
  }) {
    return ScanSessionSnapshot(
      isInitialized: isInitialized ?? this.isInitialized,
      isRunning: isRunning ?? this.isRunning,
      torchAvailable: torchAvailable ?? this.torchAvailable,
      torchOn: torchOn ?? this.torchOn,
      zoomScale: zoomScale ?? this.zoomScale,
      captureLocked: captureLocked ?? this.captureLocked,
      galleryPhase: galleryPhase ?? this.galleryPhase,
      failure: identical(failure, _unset)
          ? this.failure
          : failure as AppFailure?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScanSessionSnapshot &&
      other.isInitialized == isInitialized &&
      other.isRunning == isRunning &&
      other.torchAvailable == torchAvailable &&
      other.torchOn == torchOn &&
      other.zoomScale == zoomScale &&
      other.captureLocked == captureLocked &&
      other.galleryPhase == galleryPhase &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(
    isInitialized,
    isRunning,
    torchAvailable,
    torchOn,
    zoomScale,
    captureLocked,
    galleryPhase,
    failure,
  );
}

/// Factory used by Riverpod to create one isolated session per Scan purpose.
abstract interface class ScanSessionFactory {
  /// Creates a session with exclusive ownership of its native controller.
  ScanSession create();
}

/// App-owned scanner contract consumed by Scan presentation.
///
/// The camera is a Flutter platform view, so this boundary creates its opaque
/// view while keeping all plugin types, controllers, and lifecycle rules inside
/// the adapter. Commands and failures remain typed and injectable.
abstract interface class ScanSession implements Listenable {
  /// Last app-owned projection of native camera state.
  ScanSessionSnapshot get snapshot;

  /// Builds the opaque platform view and binds it to [scanWindow].
  ///
  /// [onCaptured] is invoked at most once until [resetCapture] is called.
  Widget buildCameraSurface({
    required Rect scanWindow,
    required Color placeholderColor,
    required ValueChanged<ScanPayload> onCaptured,
  });

  /// Records whether this presentation owner currently wants the camera live.
  Future<AppResult<void>> setActive(bool active);

  /// Applies a torch state only when the native camera reports support.
  Future<AppResult<void>> setTorchEnabled(bool enabled);

  /// Applies the plugin's normalized zoom scale in the inclusive 0...1 range.
  Future<AppResult<void>> setZoomScale(double scale);

  /// Selects one image and distinguishes cancel, no-code, and capture outcomes.
  Future<AppResult<ScanGalleryOutcome>> pickAndAnalyzeGallery();

  /// Performs a serialized stop/start after clearing a retryable failure.
  Future<AppResult<void>> restart();

  /// Re-arms the one-result gate without starting the camera by itself.
  void resetCapture();

  /// Attempts every native cleanup step and returns a redacted result.
  Future<AppResult<void>> close();
}

/// Redacted platform-driver failure classes.
enum ScanDriverFailureKind {
  permissionDenied,
  unsupported,
  unavailable,
  invalidState,
}

/// A plugin-free, non-secret failure passed from a platform adapter.
final class ScanDriverException implements Exception {
  const ScanDriverException({
    required this.code,
    required this.kind,
    this.diagnostic,
    this.stackTrace,
  });

  final String code;
  final ScanDriverFailureKind kind;
  final FailureDiagnostic? diagnostic;
  final StackTrace? stackTrace;

  @override
  String toString() => 'ScanDriverException($code)';
}

/// Plugin-neutral state supplied by the low-level camera driver.
@immutable
final class ScanDriverState {
  const ScanDriverState({
    this.isInitialized = false,
    this.isRunning = false,
    this.torchAvailable = false,
    this.torchOn = false,
    this.zoomScale = 0,
  });

  final bool isInitialized;
  final bool isRunning;
  final bool torchAvailable;
  final bool torchOn;
  final double zoomScale;

  @override
  bool operator ==(Object other) =>
      other is ScanDriverState &&
      other.isInitialized == isInitialized &&
      other.isRunning == isRunning &&
      other.torchAvailable == torchAvailable &&
      other.torchOn == torchOn &&
      other.zoomScale == zoomScale;

  @override
  int get hashCode =>
      Object.hash(isInitialized, isRunning, torchAvailable, torchOn, zoomScale);
}

/// Low-level camera operations implemented only by the platform adapter.
abstract interface class ScanCameraDriver implements Listenable {
  /// Current plugin-neutral state.
  ScanDriverState get state;

  /// Builds the native camera surface without exposing plugin types upward.
  Widget buildView({
    required Rect scanWindow,
    required Color placeholderColor,
    required ValueChanged<Iterable<String?>> onDetected,
    required ValueChanged<ScanDriverException> onFailure,
  });

  /// Starts camera capture.
  Future<void> start();

  /// Stops camera capture and releases the platform camera session.
  Future<void> stop();

  /// Sets the physical torch when supported.
  Future<void> setTorchEnabled(bool enabled);

  /// Sets the plugin-defined normalized zoom scale.
  Future<void> setZoomScale(double scale);

  /// Analyzes a selected image and returns every decoded raw QR value.
  Future<Iterable<String?>> analyzeImage(String path);

  /// Permanently disposes the native controller.
  Future<void> close();
}

/// Selects one gallery image without retaining it beyond the current command.
abstract interface class ScanGallerySource {
  /// Returns a temporary selected-image path, or null when the user cancels.
  Future<String?> selectImagePath();
}

const _unset = Object();

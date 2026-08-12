import 'dart:async';

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
    this.failure,
  });

  final bool isInitialized;
  final bool isRunning;
  final bool torchAvailable;
  final bool torchOn;
  final double zoomScale;
  final bool captureLocked;
  final AppFailure? failure;

  bool get isReady => isInitialized && isRunning && failure == null;

  ScanSessionSnapshot copyWith({
    bool? isInitialized,
    bool? isRunning,
    bool? torchAvailable,
    bool? torchOn,
    double? zoomScale,
    bool? captureLocked,
    Object? failure = _unset,
  }) {
    return ScanSessionSnapshot(
      isInitialized: isInitialized ?? this.isInitialized,
      isRunning: isRunning ?? this.isRunning,
      torchAvailable: torchAvailable ?? this.torchAvailable,
      torchOn: torchOn ?? this.torchOn,
      zoomScale: zoomScale ?? this.zoomScale,
      captureLocked: captureLocked ?? this.captureLocked,
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
      other.failure == failure;

  @override
  int get hashCode => Object.hash(
    isInitialized,
    isRunning,
    torchAvailable,
    torchOn,
    zoomScale,
    captureLocked,
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

/// Serializes native camera ownership across every session from one factory.
///
/// This remains an implementation detail of the Scan service boundary. It
/// prevents a newly opened picker from starting while a prior controller is
/// still stopping or disposing its process-wide platform camera resources.
final class ScanSessionCommandQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

/// Lifecycle-safe implementation shared by production and deterministic tests.
final class ManagedScanSession extends ChangeNotifier implements ScanSession {
  ManagedScanSession(
    this._driver,
    this._gallery, {
    ScanSessionCommandQueue? commandQueue,
  }) : _commandQueue = commandQueue ?? ScanSessionCommandQueue() {
    _driver.addListener(_synchronizeDriverState);
    _synchronizeDriverState();
  }

  final ScanCameraDriver _driver;
  final ScanGallerySource _gallery;
  final ScanSessionCommandQueue _commandQueue;
  ScanSessionSnapshot _snapshot = const ScanSessionSnapshot();
  bool _viewAttached = false;
  bool _requestedActive = true;
  bool _appActive = true;
  bool _captureLocked = false;
  bool _galleryInFlight = false;
  Completer<void>? _galleryCompletion;
  bool _disposeRequested = false;
  Future<AppResult<void>>? _closeFuture;

  @override
  ScanSessionSnapshot get snapshot => _snapshot;

  @override
  Widget buildCameraSurface({
    required Rect scanWindow,
    required Color placeholderColor,
    required ValueChanged<ScanPayload> onCaptured,
  }) {
    return _ScanLifecycleSurface(
      session: this,
      child: _driver.buildView(
        scanWindow: scanWindow,
        placeholderColor: placeholderColor,
        onDetected: (values) => _acceptDetected(values, onCaptured),
        onFailure: _recordDriverFailure,
      ),
    );
  }

  @override
  Future<AppResult<void>> setActive(bool active) {
    if (_disposeRequested) return Future.value(_unavailableResult());
    _requestedActive = active;
    return _runDriverCommand(_reconcileRunningUnsafe);
  }

  @override
  Future<AppResult<void>> setTorchEnabled(bool enabled) {
    if (_disposeRequested || !_snapshot.isReady || !_snapshot.torchAvailable) {
      return Future.value(_unavailableResult());
    }
    return _runDriverCommand(
      () => _driver.setTorchEnabled(enabled),
      action: _ScanDriverAction.torch,
      persistFailure: false,
    );
  }

  @override
  Future<AppResult<void>> setZoomScale(double scale) {
    if (_disposeRequested ||
        !_snapshot.isReady ||
        !scale.isFinite ||
        scale < 0 ||
        scale > 1) {
      return Future.value(_unavailableResult());
    }
    return _runDriverCommand(
      () => _driver.setZoomScale(scale),
      action: _ScanDriverAction.zoom,
      persistFailure: false,
    );
  }

  @override
  Future<AppResult<ScanGalleryOutcome>> pickAndAnalyzeGallery() async {
    final hasCommittedCapture = _captureLocked && _snapshot.failure == null;
    if (_disposeRequested || _galleryInFlight || hasCommittedCapture) {
      return AppResult.failure(_operationInProgressFailure());
    }
    final completion = Completer<void>();
    _galleryInFlight = true;
    _galleryCompletion = completion;
    try {
      final path = await _gallery.selectImagePath();
      if (_disposeRequested) {
        return AppResult.failure(_operationInProgressFailure());
      }
      if (path == null) {
        return const AppResult.success(ScanGalleryCancelled());
      }
      final values = await _serialize(() => _driver.analyzeImage(path));
      final selected = _selectPayload(values, ScanCaptureSource.gallery);
      switch (selected) {
        case AppFailureResult<ScanPayload?>(:final failure):
          return AppResult.failure(failure);
        case AppSuccess<ScanPayload?>(value: null):
          return const AppResult.success(ScanGalleryNoCode());
        case AppSuccess<ScanPayload?>(value: final payload?):
          _captureLocked = true;
          _setFailure(null);
          _publishCaptureLock();
          _requestedActive = false;
          unawaited(_runDriverCommand(_reconcileRunningUnsafe));
          return AppResult.success(ScanGalleryCaptured(payload));
      }
    } on ScanDriverException catch (error) {
      final failure = _mapDriverFailure(error, gallery: true);
      return AppResult.failure(failure);
    } catch (error, stackTrace) {
      final failure = _unexpectedFailure(error, stackTrace, gallery: true);
      return AppResult.failure(failure);
    } finally {
      _galleryInFlight = false;
      if (identical(_galleryCompletion, completion)) {
        _galleryCompletion = null;
      }
      completion.complete();
    }
  }

  @override
  Future<AppResult<void>> restart() async {
    if (_disposeRequested) return _unavailableResult();
    _captureLocked = false;
    _publishCaptureLock();
    _setFailure(null);
    _requestedActive = false;
    final stopped = await _runDriverCommand(_reconcileRunningUnsafe);
    if (stopped is AppFailureResult<void>) return stopped;
    _requestedActive = true;
    return _runDriverCommand(_reconcileRunningUnsafe);
  }

  @override
  void resetCapture() {
    if (_disposeRequested) return;
    _captureLocked = false;
    _publishCaptureLock();
    _setFailure(null);
  }

  void _attachView() {
    if (_disposeRequested || _viewAttached) return;
    _viewAttached = true;
    unawaited(_runDriverCommand(_reconcileRunningUnsafe));
  }

  void _detachView() {
    if (_disposeRequested || !_viewAttached) return;
    _viewAttached = false;
    unawaited(_runDriverCommand(_reconcileRunningUnsafe));
  }

  void _setLifecycle(AppLifecycleState lifecycle) {
    if (_disposeRequested) return;
    final active = lifecycle == AppLifecycleState.resumed;
    if (active == _appActive) return;
    _appActive = active;
    unawaited(_runDriverCommand(_reconcileRunningUnsafe));
  }

  Future<void> _reconcileRunningUnsafe() async {
    final shouldRun =
        _viewAttached && _requestedActive && _appActive && !_captureLocked;
    if (shouldRun && !_driver.state.isRunning) {
      await _driver.start();
      _setFailure(null);
      return;
    }
    if (!shouldRun && _driver.state.isRunning) {
      await _driver.stop();
    }
  }

  void _acceptDetected(
    Iterable<String?> values,
    ValueChanged<ScanPayload> onCaptured,
  ) {
    if (_disposeRequested ||
        _captureLocked ||
        !_viewAttached ||
        !_requestedActive ||
        !_appActive ||
        _galleryInFlight ||
        !_driver.state.isRunning) {
      return;
    }
    final selected = _selectPayload(values, ScanCaptureSource.camera);
    switch (selected) {
      case AppSuccess<ScanPayload?>(value: null):
        return;
      case AppSuccess<ScanPayload?>(value: final payload?):
        _captureLocked = true;
        _requestedActive = false;
        unawaited(_runDriverCommand(_reconcileRunningUnsafe));
        onCaptured(payload);
        _publishCaptureLock();
      case AppFailureResult<ScanPayload?>(:final failure):
        _captureLocked = true;
        _publishCaptureLock();
        _requestedActive = false;
        _setFailure(failure);
        unawaited(_runDriverCommand(_reconcileRunningUnsafe));
    }
  }

  AppResult<ScanPayload?> _selectPayload(
    Iterable<String?> values,
    ScanCaptureSource source,
  ) {
    ScanPayload? selected;
    for (final raw in values) {
      if (raw == null || raw.trim().isEmpty) continue;
      final parsed = _parsePayload(raw, source);
      if (parsed case AppFailureResult<ScanPayload>(:final failure)) {
        return AppResult.failure(failure);
      }
      final candidate = (parsed as AppSuccess<ScanPayload>).value;
      if (selected != null && selected.value != candidate.value) {
        return AppResult.failure(_ambiguousPayloadFailure());
      }
      selected = candidate;
    }
    return AppResult.success(selected);
  }

  AppResult<ScanPayload> _parsePayload(String raw, ScanCaptureSource source) {
    try {
      return AppResult.success(ScanPayload.parse(raw, source: source));
    } on InvalidScanPayloadException catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: 'scan_payload_invalid',
          kind: AppFailureKind.validation,
          userMessage: 'This code is not a supported payment value.',
          retryable: false,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  void _synchronizeDriverState() {
    if (_disposeRequested) return;
    final driver = _driver.state;
    _replaceSnapshot(
      _snapshot.copyWith(
        isInitialized: driver.isInitialized,
        isRunning: driver.isRunning,
        torchAvailable: driver.torchAvailable,
        torchOn: driver.torchOn,
        zoomScale: driver.zoomScale,
      ),
    );
  }

  void _recordDriverFailure(ScanDriverException error) {
    if (_disposeRequested) return;
    if (_captureLocked && _snapshot.failure == null) return;
    _captureLocked = true;
    _publishCaptureLock();
    _requestedActive = false;
    _setFailure(_mapDriverFailure(error));
    unawaited(_runDriverCommand(_reconcileRunningUnsafe));
  }

  void _setFailure(AppFailure? failure) {
    _replaceSnapshot(_snapshot.copyWith(failure: failure));
  }

  void _publishCaptureLock() {
    _replaceSnapshot(_snapshot.copyWith(captureLocked: _captureLocked));
  }

  void _replaceSnapshot(ScanSessionSnapshot next) {
    if (_disposeRequested || next == _snapshot) return;
    _snapshot = next;
    notifyListeners();
  }

  Future<AppResult<void>> _runDriverCommand(
    Future<void> Function() command, {
    _ScanDriverAction action = _ScanDriverAction.camera,
    bool persistFailure = true,
  }) {
    if (_disposeRequested) return Future.value(_unavailableResult());
    return _serialize(() async {
      try {
        await command();
        return const AppResult.success(null);
      } on ScanDriverException catch (error) {
        final failure = _mapDriverFailure(error, action: action);
        if (persistFailure) _setFailure(failure);
        return AppResult.failure(failure);
      } catch (error, stackTrace) {
        final failure = _unexpectedFailure(error, stackTrace, action: action);
        if (persistFailure) _setFailure(failure);
        return AppResult.failure(failure);
      }
    });
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    return _commandQueue.run(operation);
  }

  @override
  Future<AppResult<void>> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _disposeRequested = true;
    final completer = Completer<AppResult<void>>();
    _closeFuture = completer.future;
    final galleryCompletion = _galleryCompletion;
    if (galleryCompletion == null) {
      _scheduleClose(completer);
    } else {
      unawaited(_closeAfterGallery(galleryCompletion, completer));
    }
    return completer.future;
  }

  Future<void> _closeAfterGallery(
    Completer<void> galleryCompletion,
    Completer<AppResult<void>> completer,
  ) async {
    await galleryCompletion.future;
    _scheduleClose(completer);
  }

  void _scheduleClose(Completer<AppResult<void>> completer) {
    unawaited(
      _serialize(() async {
        AppFailure? failure;
        _requestedActive = false;
        _viewAttached = false;
        try {
          if (_driver.state.isRunning) await _driver.stop();
        } catch (error, stackTrace) {
          failure = _cleanupFailure(error, stackTrace);
        }
        try {
          _driver.removeListener(_synchronizeDriverState);
        } catch (error, stackTrace) {
          failure ??= _cleanupFailure(error, stackTrace);
        }
        try {
          await _driver.close();
        } catch (error, stackTrace) {
          failure ??= _cleanupFailure(error, stackTrace);
        }
        try {
          super.dispose();
        } catch (error, stackTrace) {
          failure ??= _cleanupFailure(error, stackTrace);
        }
        if (!completer.isCompleted) {
          completer.complete(
            failure == null
                ? const AppResult.success(null)
                : AppResult.failure(failure),
          );
        }
      }),
    );
  }

  AppResult<void> _unavailableResult() =>
      AppResult.failure(_operationInProgressFailure());

  static AppFailure _operationInProgressFailure() => const AppFailure(
    code: 'scan_operation_unavailable',
    kind: AppFailureKind.conflict,
    userMessage: 'Wait for the current scan action to finish.',
    retryable: false,
  );

  static AppFailure _ambiguousPayloadFailure() => const AppFailure(
    code: 'scan_payload_ambiguous',
    kind: AppFailureKind.validation,
    userMessage: 'More than one payment code was detected. Scan one at a time.',
    retryable: true,
  );

  static AppFailure _mapDriverFailure(
    ScanDriverException error, {
    bool gallery = false,
    _ScanDriverAction action = _ScanDriverAction.camera,
  }) {
    if (!gallery && action != _ScanDriverAction.camera) {
      return _mapControlFailure(error, action);
    }
    final (kind, message, retryable) = switch (error.kind) {
      ScanDriverFailureKind.permissionDenied => (
        AppFailureKind.authentication,
        gallery
            ? 'Photo access is unavailable. Choose a code another way.'
            : 'Allow camera access in system settings to scan a code.',
        false,
      ),
      ScanDriverFailureKind.unsupported => (
        AppFailureKind.unsupported,
        gallery
            ? 'Scanning codes from images is not supported on this device.'
            : 'Camera scanning is not supported on this device.',
        false,
      ),
      ScanDriverFailureKind.invalidState => (
        AppFailureKind.conflict,
        'The scanner is changing state. Try again.',
        true,
      ),
      ScanDriverFailureKind.unavailable => (
        AppFailureKind.unavailable,
        gallery
            ? 'The selected image could not be scanned.'
            : 'The camera could not be started.',
        true,
      ),
    };
    return AppFailure(
      code: error.code,
      kind: kind,
      userMessage: message,
      retryable: retryable,
      cause: error.diagnostic,
      stackTrace: error.stackTrace,
    );
  }

  static AppFailure _unexpectedFailure(
    Object error,
    StackTrace stackTrace, {
    bool gallery = false,
    _ScanDriverAction action = _ScanDriverAction.camera,
  }) {
    final controlMessage = switch (action) {
      _ScanDriverAction.camera => null,
      _ScanDriverAction.torch => 'The flashlight could not be changed.',
      _ScanDriverAction.zoom => 'The zoom level could not be changed.',
    };
    return AppFailure(
      code: gallery
          ? 'scan_gallery_failed'
          : switch (action) {
              _ScanDriverAction.camera => 'scan_camera_failed',
              _ScanDriverAction.torch => 'scan_torch_failed',
              _ScanDriverAction.zoom => 'scan_zoom_failed',
            },
      kind: AppFailureKind.unavailable,
      userMessage:
          controlMessage ??
          (gallery
              ? 'The selected image could not be scanned.'
              : 'The camera could not be started.'),
      retryable: true,
      cause: FailureMapper.diagnosticCause(error),
      stackTrace: stackTrace,
    );
  }

  static AppFailure _cleanupFailure(Object error, StackTrace stackTrace) {
    final diagnostic = error is ScanDriverException
        ? error.diagnostic
        : FailureMapper.diagnosticCause(error);
    return AppFailure(
      code: 'scan_camera_cleanup_failed',
      kind: AppFailureKind.unavailable,
      userMessage: 'The scanner could not be fully released.',
      retryable: false,
      cause: diagnostic,
      stackTrace: error is ScanDriverException
          ? error.stackTrace ?? stackTrace
          : stackTrace,
    );
  }

  static AppFailure _mapControlFailure(
    ScanDriverException error,
    _ScanDriverAction action,
  ) {
    final noun = action == _ScanDriverAction.torch ? 'flashlight' : 'zoom';
    final (kind, message, retryable) = switch (error.kind) {
      ScanDriverFailureKind.permissionDenied => (
        AppFailureKind.authentication,
        'Camera access is required before using the $noun.',
        false,
      ),
      ScanDriverFailureKind.unsupported => (
        AppFailureKind.unsupported,
        'The $noun is not supported on this device.',
        false,
      ),
      ScanDriverFailureKind.invalidState => (
        AppFailureKind.conflict,
        'The $noun is unavailable while the camera changes state.',
        true,
      ),
      ScanDriverFailureKind.unavailable => (
        AppFailureKind.unavailable,
        action == _ScanDriverAction.torch
            ? 'The flashlight could not be changed.'
            : 'The zoom level could not be changed.',
        true,
      ),
    };
    return AppFailure(
      code: error.code,
      kind: kind,
      userMessage: message,
      retryable: retryable,
      cause: error.diagnostic,
      stackTrace: error.stackTrace,
    );
  }
}

class _ScanLifecycleSurface extends StatefulWidget {
  const _ScanLifecycleSurface({required this.session, required this.child});

  final ManagedScanSession session;
  final Widget child;

  @override
  State<_ScanLifecycleSurface> createState() => _ScanLifecycleSurfaceState();
}

class _ScanLifecycleSurfaceState extends State<_ScanLifecycleSurface>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null) widget.session._setLifecycle(lifecycle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.session._attachView();
    });
  }

  @override
  void didUpdateWidget(_ScanLifecycleSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session) return;
    oldWidget.session._detachView();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null) widget.session._setLifecycle(lifecycle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.session._attachView();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.session._setLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session._detachView();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

const _unset = Object();

enum _ScanDriverAction { camera, torch, zoom }

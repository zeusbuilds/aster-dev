import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';
import 'scan_lifecycle_surface.dart';
import 'scan_session_contract.dart';

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
final class ManagedScanSession extends ChangeNotifier
    implements ScanSession, ScanSessionContext {
  ManagedScanSession(
    this._driver,
    this._gallery, {
    ScanSessionCommandQueue? commandQueue,
    Future<bool> Function(ScanPayload)? validatePayload,
    Object? Function()? contextToken,
    // Public option names stay independent of private implementation fields.
    // ignore: prefer_initializing_formals
  }) : _contextToken = contextToken,
       // ignore: prefer_initializing_formals
       _validatePayload = validatePayload,
       _commandQueue = commandQueue ?? ScanSessionCommandQueue() {
    _driver.addListener(_synchronizeDriverState);
    _synchronizeDriverState();
  }

  final ScanCameraDriver _driver;
  final ScanGallerySource _gallery;
  final ScanSessionCommandQueue _commandQueue;
  final Future<bool> Function(ScanPayload)? _validatePayload;
  final Object? Function()? _contextToken;
  final Stopwatch _clock = Stopwatch()..start();
  final Map<String, Duration> _rejectedUntil = <String, Duration>{};
  Timer? _recoveryTimer;
  int _recoveryAttempt = 0;
  int _captureRevision = 0;
  int _viewRevision = 0;
  bool _validatingCamera = false;
  bool _needsRestart = false;
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
  Object? get contextToken => _contextToken?.call();

  @override
  Widget buildCameraSurface({
    required Rect scanWindow,
    required Color placeholderColor,
    required ValueChanged<ScanPayload> onCaptured,
  }) {
    return ScanLifecycleSurface(
      owner: this,
      onAttach: _attachView,
      onDetach: _detachView,
      onLifecycleChanged: _setLifecycle,
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
    if (!active) {
      _captureRevision++;
      _cancelRecovery();
    }
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
  Future<AppResult<void>> setZoomRatio(double ratio) {
    if (_disposeRequested ||
        !_snapshot.isReady ||
        !ratio.isFinite ||
        _snapshot.zoom?.isValid != true ||
        ratio < _snapshot.zoom!.minimum ||
        ratio > _snapshot.zoom!.maximum) {
      return Future.value(_unavailableResult());
    }
    return _runDriverCommand(
      () => _driver.setZoomRatio(ratio),
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
    final contextToken = _contextToken?.call();
    final viewRevision = _viewRevision;
    _galleryInFlight = true;
    _galleryCompletion = completion;
    _replaceSnapshot(
      _snapshot.copyWith(galleryPhase: ScanGalleryPhase.selecting),
    );
    try {
      final path = await _gallery.selectImagePath();
      if (_disposeRequested ||
          viewRevision != _viewRevision ||
          contextToken != _contextToken?.call() ||
          !_appActive) {
        return AppResult.failure(_operationInProgressFailure());
      }
      if (path == null) {
        return const AppResult.success(ScanGalleryCancelled());
      }
      final analysisRevision = _captureRevision;
      final values = await _serialize(() async {
        if (_disposeRequested) return const <String?>[];
        _replaceSnapshot(
          _snapshot.copyWith(galleryPhase: ScanGalleryPhase.analyzing),
        );
        return _driver.analyzeImage(path);
      });
      if (_disposeRequested ||
          viewRevision != _viewRevision ||
          analysisRevision != _captureRevision ||
          contextToken != _contextToken?.call() ||
          !_appActive) {
        return AppResult.failure(_operationInProgressFailure());
      }
      final selected = await _selectPayload(
        values,
        ScanCaptureSource.gallery,
        isCurrent: () =>
            !_disposeRequested && analysisRevision == _captureRevision,
      );
      if (_disposeRequested ||
          analysisRevision != _captureRevision ||
          contextToken != _contextToken?.call() ||
          !_appActive) {
        return AppResult.failure(_operationInProgressFailure());
      }
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
      _replaceSnapshot(_snapshot.copyWith(galleryPhase: ScanGalleryPhase.idle));
      if (identical(_galleryCompletion, completion)) {
        _galleryCompletion = null;
      }
      completion.complete();
    }
  }

  @override
  Future<AppResult<void>> restart() async {
    if (_disposeRequested) return _unavailableResult();
    _captureRevision++;
    _cancelRecovery();
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
    _captureRevision++;
    _captureLocked = false;
    _publishCaptureLock();
    _setFailure(null);
  }

  void _attachView() {
    if (_disposeRequested || _viewAttached) return;
    _viewAttached = true;
    _viewRevision++;
    _recoveryAttempt = 0;
    unawaited(_runDriverCommand(_reconcileRunningUnsafe));
  }

  void _detachView() {
    if (_disposeRequested || !_viewAttached) return;
    _viewAttached = false;
    _viewRevision++;
    _captureRevision++;
    _cancelRecovery();
    unawaited(_runDriverCommand(_reconcileRunningUnsafe));
  }

  void _setLifecycle(AppLifecycleState lifecycle) {
    if (_disposeRequested) return;
    final active = lifecycle == AppLifecycleState.resumed;
    if (active == _appActive) return;
    _appActive = active;
    _captureRevision++;
    _cancelRecovery();
    if (active) _recoveryAttempt = 0;
    unawaited(_runDriverCommand(_reconcileRunningUnsafe));
  }

  bool get _wantsCamera =>
      !_disposeRequested &&
      _viewAttached &&
      _requestedActive &&
      _appActive &&
      !_captureLocked &&
      !_galleryInFlight;

  Future<void> _reconcileRunningUnsafe() async {
    if (_wantsCamera) {
      if (_needsRestart && _driver.state.isRunning) await _driver.stop();
      if (!_driver.state.isRunning) await _driver.start();
      // A permission sheet can change lifecycle while start is in flight. Its
      // serialized follow-up owns stopping; never accept a late camera frame.
      _needsRestart = false;
      _recoveryAttempt = 0;
      _cancelRecovery();
      _setFailure(null);
      return;
    }
    if (_driver.state.isRunning) await _driver.stop();
  }

  void _acceptDetected(
    Iterable<String?> values,
    ValueChanged<ScanPayload> onCaptured,
  ) {
    if (!_wantsCamera || _validatingCamera || !_driver.state.isRunning) return;
    final revision = _captureRevision;
    _validatingCamera = true;
    // A bounded snapshot preserves detector order without keeping camera/plugin
    // buffers alive while a read-only native RGB decode is pending.
    final candidates = values.take(16).toList(growable: false);
    unawaited(() async {
      try {
        final selected = await _selectPayload(
          candidates,
          ScanCaptureSource.camera,
          isCurrent: () => _wantsCamera && revision == _captureRevision,
        );
        if (!_wantsCamera || revision != _captureRevision) return;
        if (selected case AppSuccess<ScanPayload?>(value: final payload?)) {
          _captureLocked = true;
          _setFailure(null);
          _requestedActive = false;
          _cancelRecovery();
          unawaited(_runDriverCommand(_reconcileRunningUnsafe));
          onCaptured(payload);
          _publishCaptureLock();
        }
        // Invalid/unsupported QR values do not pause capture or create status.
      } finally {
        _validatingCamera = false;
      }
    }());
  }

  Future<AppResult<ScanPayload?>> _selectPayload(
    Iterable<String?> values,
    ScanCaptureSource source, {
    bool Function()? isCurrent,
  }) async {
    for (final raw in values.take(16)) {
      if (isCurrent != null && !isCurrent()) {
        return const AppResult.success(null);
      }
      if (raw == null || raw.trim().isEmpty) continue;
      final parsed = _parsePayload(raw, source);
      if (parsed is! AppSuccess<ScanPayload>) continue;
      final candidate = parsed.value;
      final isCamera = source == ScanCaptureSource.camera;
      if (isCamera) {
        final now = _clock.elapsed;
        _rejectedUntil.removeWhere((_, until) => until <= now);
        if (_rejectedUntil.containsKey(candidate.value)) continue;
      }
      bool accepted;
      try {
        accepted =
            await (_validatePayload?.call(candidate) ?? Future.value(true))
                .timeout(const Duration(seconds: 5), onTimeout: () => false);
      } catch (_) {
        accepted = false;
      }
      if (_disposeRequested || (isCurrent != null && !isCurrent())) {
        return const AppResult.success(null);
      }
      if (accepted) return AppResult.success(candidate);
      if (isCamera) {
        if (_rejectedUntil.length >= 32) {
          _rejectedUntil.remove(_rejectedUntil.keys.first);
        }
        _rejectedUntil[candidate.value] =
            _clock.elapsed + const Duration(seconds: 2);
      }
    }
    return const AppResult.success(null);
  }

  void _cancelRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
  }

  void _scheduleRecovery(AppFailure failure) {
    if (!failure.retryable) {
      _cancelRecovery();
      return;
    }
    if (!_wantsCamera || _recoveryTimer != null) return;
    // There is no scanner-session expiry. Transient camera recovery stays quiet
    // while visible, backs off to 30 seconds, and stops on hide/dispose/capture.
    final seconds = _recoveryAttempt < 5 ? 1 << _recoveryAttempt : 30;
    _recoveryAttempt++;
    _recoveryTimer = Timer(Duration(seconds: seconds), () {
      _recoveryTimer = null;
      if (!_wantsCamera) return;
      _needsRestart = true;
      unawaited(_runDriverCommand(_reconcileRunningUnsafe));
    });
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
        zoom:
            driver.isInitialized &&
                driver.isRunning &&
                (driver.zoom?.isValid ?? false)
            ? driver.zoom
            : null,
      ),
    );
  }

  void _recordDriverFailure(ScanDriverException error) {
    if (_disposeRequested || _captureLocked || !_requestedActive) return;
    final failure = _mapDriverFailure(error);
    _needsRestart = true;
    _setFailure(failure);
    _scheduleRecovery(failure);
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
        if (persistFailure) {
          _setFailure(failure);
          _scheduleRecovery(failure);
        }
        return AppResult.failure(failure);
      } catch (error, stackTrace) {
        final failure = _unexpectedFailure(error, stackTrace, action: action);
        if (persistFailure) {
          _setFailure(failure);
          _scheduleRecovery(failure);
        }
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
    _captureRevision++;
    _cancelRecovery();
    _rejectedUntil.clear();
    _clock.stop();
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

enum _ScanDriverAction { camera, torch, zoom }

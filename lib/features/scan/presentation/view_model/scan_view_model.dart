import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../../shared/feedback/feedback.dart';
import '../../data/services/services.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

part 'scan_view_model.g.dart';

/// Coordinates one purpose-scoped Scan session and its semantic feedback.
@riverpod
class ScanViewModel extends _$ScanViewModel {
  late ScanSession _session;
  ScanSession? _listenedSession;
  void Function()? _sessionListener;
  var _operationRevision = 0;

  @override
  ScanState build(ScanPurpose purpose) {
    final session = ref.watch(scanSessionProvider(purpose));
    final previousSession = _listenedSession;
    final previousListener = _sessionListener;
    if (previousSession != null && previousListener != null) {
      previousSession.removeListener(previousListener);
    }
    _operationRevision += 1;
    _session = session;
    void synchronizeSession() => _synchronizeSession(session);
    _listenedSession = session;
    _sessionListener = synchronizeSession;
    session.addListener(synchronizeSession);
    ref.onDispose(() => session.removeListener(synchronizeSession));
    return _stateFromSession(session.snapshot);
  }

  /// Accepts exactly one camera payload until the caller resumes this session.
  bool acceptCameraPayload(ScanPayload payload) {
    if (state.captureLocked) return false;
    _operationRevision += 1;
    state = state.copyWith(captureLocked: true, operation: null, failure: null);
    unawaited(
      ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.lightImpact),
    );
    return true;
  }

  /// Toggles the real torch only after the camera reports it available.
  Future<AppResult<void>> toggleFlash() async {
    if (!state.canToggleFlash) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    final session = _session;
    final revision = ++_operationRevision;
    final next = !state.flashOn;
    state = state.copyWith(
      operation: ScanOperation.togglingTorch,
      failure: null,
    );
    final result = await session.setTorchEnabled(next);
    if (!_isCurrentOperation(session, revision)) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    return switch (result) {
      AppSuccess<void>() => () {
        state = state.copyWith(
          flashOn: session.snapshot.torchOn,
          operation: null,
        );
        unawaited(
          ref
              .read(hapticFeedbackServiceProvider)
              .trigger(HapticIntent.selection),
        );
        return result;
      }(),
      AppFailureResult<void>(:final failure) => () {
        _applyControlFailure(failure);
        return result;
      }(),
    };
  }

  /// Advances one normalized zoom level without claiming optical magnification.
  Future<AppResult<void>> cycleZoom() async {
    if (!state.canChangeZoom) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    final session = _session;
    final revision = ++_operationRevision;
    final next = state.zoomPreset.next;
    state = state.copyWith(
      operation: ScanOperation.changingZoom,
      failure: null,
    );
    final result = await session.setZoomScale(next.scale);
    if (!_isCurrentOperation(session, revision)) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    return switch (result) {
      AppSuccess<void>() => () {
        state = state.copyWith(
          zoomPreset: ScanZoomPreset.nearest(session.snapshot.zoomScale),
          operation: null,
        );
        unawaited(
          ref
              .read(hapticFeedbackServiceProvider)
              .trigger(HapticIntent.selection),
        );
        return result;
      }(),
      AppFailureResult<void>(:final failure) => () {
        _applyControlFailure(failure);
        return result;
      }(),
    };
  }

  /// Selects and analyzes one gallery image behind the platform boundary.
  Future<AppResult<ScanGalleryOutcome>> scanGallery() async {
    if (!state.canUseGallery) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    final session = _session;
    final revision = ++_operationRevision;
    final cameraFailure = state.failure;
    state = state.copyWith(operation: ScanOperation.selectingGallery);
    final paused = await session.setActive(false);
    if (!_isCurrentOperation(session, revision)) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    if (paused case AppFailureResult<void>(:final failure)) {
      if (ref.mounted) {
        _applyOperationFailure(failure);
      }
      return AppResult.failure(failure);
    }
    final result = await session.pickAndAnalyzeGallery();
    if (!_isCurrentOperation(session, revision)) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    switch (result) {
      case AppSuccess<ScanGalleryOutcome>(:final value):
        final captured = value is ScanGalleryCaptured;
        state = state.copyWith(
          captureLocked: captured,
          operation: null,
          failure: captured ? null : cameraFailure,
        );
        if (captured) {
          unawaited(
            ref
                .read(hapticFeedbackServiceProvider)
                .trigger(HapticIntent.lightImpact),
          );
        } else {
          if (value is ScanGalleryNoCode) {
            unawaited(
              ref
                  .read(hapticFeedbackServiceProvider)
                  .trigger(HapticIntent.warning),
            );
          }
          unawaited(session.setActive(true));
        }
      case AppFailureResult<ScanGalleryOutcome>(:final failure):
        state = state.copyWith(operation: null, failure: cameraFailure);
        final intent =
            failure.kind == AppFailureKind.authentication ||
                failure.kind == AppFailureKind.unsupported
            ? HapticIntent.warning
            : HapticIntent.error;
        unawaited(ref.read(hapticFeedbackServiceProvider).trigger(intent));
        unawaited(session.setActive(true));
    }
    return result;
  }

  /// Pauses the native session before another route covers this screen.
  Future<AppResult<void>> pauseForNavigation() async {
    if (state.isBusy) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    final session = _session;
    final revision = ++_operationRevision;
    state = state.copyWith(
      operation: ScanOperation.pausingForNavigation,
      failure: null,
    );
    final result = await session.setActive(false);
    if (!_isCurrentOperation(session, revision)) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    switch (result) {
      case AppSuccess<void>():
        return result;
      case AppFailureResult<void>(:final failure):
        _applyOperationFailure(failure);
        return result;
    }
  }

  /// Re-arms one-result detection after a covering route returns.
  Future<AppResult<void>> resumeAfterNavigation() async {
    final session = _session;
    final revision = ++_operationRevision;
    session.resetCapture();
    if (ref.mounted) {
      state = state.copyWith(
        captureLocked: false,
        operation: null,
        failure: null,
      );
    }
    final result = await session.setActive(true);
    if (!_isCurrentOperation(session, revision)) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    if (result case AppFailureResult<void>(:final failure)) {
      _applyOperationFailure(failure);
    }
    return result;
  }

  /// Retries a retryable camera startup failure through a full stop/start.
  Future<bool> retryCamera() async {
    if (state.isBusy || !state.canRetry) return false;
    final session = _session;
    final revision = ++_operationRevision;
    state = state.copyWith(operation: ScanOperation.restarting, failure: null);
    final result = await session.restart();
    if (!_isCurrentOperation(session, revision)) return false;
    return switch (result) {
      AppSuccess<void>() => () {
        state = state.copyWith(operation: null, failure: null);
        return true;
      }(),
      AppFailureResult<void>(:final failure) => () {
        _applyOperationFailure(failure);
        return false;
      }(),
    };
  }

  void _synchronizeSession(ScanSession session) {
    if (!ref.mounted || !identical(session, _session)) return;
    final snapshot = session.snapshot;
    final previousFailure = state.failure;
    state = state.copyWith(
      cameraInitialized: snapshot.isInitialized,
      cameraRunning: snapshot.isRunning,
      torchAvailable: snapshot.torchAvailable,
      flashOn: snapshot.torchOn,
      zoomPreset: ScanZoomPreset.nearest(snapshot.zoomScale),
      captureLocked: snapshot.captureLocked,
      failure: snapshot.failure,
    );
    final failure = snapshot.failure;
    if (failure != null && failure != previousFailure) {
      final intent = failure.kind == AppFailureKind.authentication
          ? HapticIntent.warning
          : HapticIntent.error;
      unawaited(ref.read(hapticFeedbackServiceProvider).trigger(intent));
    }
  }

  void _applyOperationFailure(AppFailure failure) {
    final shouldTriggerFeedback = state.failure != failure;
    state = state.copyWith(operation: null, failure: failure);
    if (!shouldTriggerFeedback) return;
    final intent = failure.kind == AppFailureKind.authentication
        ? HapticIntent.warning
        : HapticIntent.error;
    unawaited(ref.read(hapticFeedbackServiceProvider).trigger(intent));
  }

  void _applyControlFailure(AppFailure failure) {
    state = state.copyWith(operation: null);
    final intent = failure.kind == AppFailureKind.authentication
        ? HapticIntent.warning
        : HapticIntent.error;
    unawaited(ref.read(hapticFeedbackServiceProvider).trigger(intent));
  }

  bool _isCurrentOperation(ScanSession session, int revision) {
    return ref.mounted &&
        identical(session, _session) &&
        revision == _operationRevision;
  }

  static ScanState _stateFromSession(ScanSessionSnapshot snapshot) {
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

  static AppFailure _operationUnavailableFailure() => const AppFailure(
    code: 'scan_operation_unavailable',
    kind: AppFailureKind.conflict,
    userMessage: 'Wait for the current scan action to finish.',
    retryable: false,
  );
}

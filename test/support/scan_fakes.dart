import 'dart:async';
import 'dart:collection';

import 'package:aster/core/core.dart';
import 'package:aster/features/scan/data/services/scan_session_contract.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:flutter/material.dart';

final class FakeScanSession extends ChangeNotifier
    implements ScanSession, ScanSessionContext {
  @override
  Object? contextToken;

  ScanSessionSnapshot current = const ScanSessionSnapshot(
    isInitialized: true,
    isRunning: true,
    torchAvailable: true,
    zoom: ScanZoomRange(minimum: 1, maximum: 3, current: 1),
  );
  AppResult<void>? activeResult;
  AppResult<void>? torchResult;
  AppResult<void>? zoomResult;
  AppResult<void>? restartResult;
  AppResult<void>? closeResult;
  Completer<AppResult<void>>? torchGate;
  Completer<AppResult<void>>? activeGate;
  Completer<AppResult<void>>? zoomGate;
  Completer<AppResult<void>>? restartGate;
  double? reportedZoomRatio;
  AppResult<ScanGalleryOutcome> galleryResult = const AppResult.success(
    ScanGalleryCancelled(),
  );
  Completer<AppResult<ScanGalleryOutcome>>? galleryGate;
  final activeValues = <bool>[];
  final torchValues = <bool>[];
  final zoomValues = <double>[];
  var resetCaptureCalls = 0;
  var restartCalls = 0;
  var galleryCalls = 0;
  var closeCalls = 0;
  var _closed = false;
  ValueChanged<ScanPayload>? _onCaptured;
  final Set<VoidCallback> _observedListeners = <VoidCallback>{};

  int get listenerCount => _observedListeners.length;

  @override
  void addListener(VoidCallback listener) {
    _observedListeners.add(listener);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _observedListeners.remove(listener);
    super.removeListener(listener);
  }

  @override
  ScanSessionSnapshot get snapshot => current;

  void replaceSnapshot(ScanSessionSnapshot value) {
    current = value;
    notifyListeners();
  }

  void emitCamera(String value) {
    _onCaptured?.call(
      ScanPayload.parse(value, source: ScanCaptureSource.camera),
    );
    replaceSnapshot(current.copyWith(captureLocked: true));
  }

  @override
  Widget buildCameraSurface({
    required Rect scanWindow,
    required Color placeholderColor,
    required ValueChanged<ScanPayload> onCaptured,
  }) {
    _onCaptured = onCaptured;
    return ColoredBox(
      key: const ValueKey('fake-scan-camera'),
      color: placeholderColor,
    );
  }

  @override
  Future<AppResult<void>> setActive(bool active) async {
    activeValues.add(active);
    final gate = activeGate;
    if (gate != null) return gate.future;
    return activeResult ?? const AppResult.success(null);
  }

  @override
  Future<AppResult<void>> setTorchEnabled(bool enabled) async {
    torchValues.add(enabled);
    final result =
        await (torchGate?.future ??
            Future.value(torchResult ?? const AppResult.success(null)));
    if (result is AppSuccess<void>) {
      replaceSnapshot(current.copyWith(torchOn: enabled));
    }
    return result;
  }

  @override
  Future<AppResult<void>> setZoomRatio(double ratio) async {
    zoomValues.add(ratio);
    final result =
        await (zoomGate?.future ??
            Future.value(zoomResult ?? const AppResult.success(null)));
    if (result is AppSuccess<void> &&
        current.zoom != null &&
        current.isRunning) {
      replaceSnapshot(
        current.copyWith(
          zoom: ScanZoomRange(
            minimum: current.zoom!.minimum,
            maximum: current.zoom!.maximum,
            current: reportedZoomRatio ?? ratio,
          ),
        ),
      );
    }
    return result;
  }

  @override
  Future<AppResult<ScanGalleryOutcome>> pickAndAnalyzeGallery() async {
    galleryCalls += 1;
    final gate = galleryGate;
    if (gate != null) return gate.future;
    return galleryResult;
  }

  @override
  Future<AppResult<void>> restart() async {
    restartCalls += 1;
    final gate = restartGate;
    if (gate != null) return gate.future;
    return restartResult ?? const AppResult.success(null);
  }

  @override
  void resetCapture() {
    resetCaptureCalls += 1;
    replaceSnapshot(current.copyWith(captureLocked: false, failure: null));
  }

  @override
  Future<AppResult<void>> close() async {
    if (_closed) return const AppResult.success(null);
    _closed = true;
    closeCalls += 1;
    _observedListeners.clear();
    super.dispose();
    return closeResult ?? const AppResult.success(null);
  }
}

final class QueueScanSessionFactory implements ScanSessionFactory {
  QueueScanSessionFactory(Iterable<ScanSession> sessions)
    : _sessions = Queue<ScanSession>.of(sessions);

  final Queue<ScanSession> _sessions;

  @override
  ScanSession create() => _sessions.removeFirst();
}

final class FakeScanCameraDriver extends ChangeNotifier
    implements ScanCameraDriver {
  ScanDriverState current = const ScanDriverState();
  ScanDriverException? startFailure;
  ScanDriverException? stopFailure;
  ScanDriverException? torchFailure;
  ScanDriverException? zoomFailure;
  ScanDriverException? analyzeFailure;
  ScanDriverException? closeFailure;
  Iterable<String?> analyzedValues = const [];
  Completer<void>? startGate;
  Completer<void>? closeGate;
  Completer<Iterable<String?>>? analyzeGate;
  final commandLog = <String>[];
  var closeCalls = 0;
  ValueChanged<Iterable<String?>>? _onDetected;
  ValueChanged<ScanDriverException>? _onFailure;

  @override
  ScanDriverState get state => current;

  @override
  Widget buildView({
    required Rect scanWindow,
    required Color placeholderColor,
    required ValueChanged<Iterable<String?>> onDetected,
    required ValueChanged<ScanDriverException> onFailure,
  }) {
    _onDetected = onDetected;
    _onFailure = onFailure;
    return ColoredBox(
      key: const ValueKey('fake-scan-driver'),
      color: placeholderColor,
    );
  }

  void emit(Iterable<String?> values) => _onDetected?.call(values);

  void emitFailure(ScanDriverException failure) => _onFailure?.call(failure);

  @override
  Future<void> start() async {
    commandLog.add('start');
    final failure = startFailure;
    if (failure != null) throw failure;
    await startGate?.future;
    current = const ScanDriverState(
      isInitialized: true,
      isRunning: true,
      torchAvailable: true,
      zoom: ScanZoomRange(minimum: 1, maximum: 3, current: 1),
    );
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    commandLog.add('stop');
    final failure = stopFailure;
    if (failure != null) throw failure;
    current = ScanDriverState(
      isInitialized: current.isInitialized,
      torchAvailable: current.torchAvailable,
      zoom: current.zoom,
    );
    notifyListeners();
  }

  @override
  Future<void> setTorchEnabled(bool enabled) async {
    commandLog.add('torch:$enabled');
    final failure = torchFailure;
    if (failure != null) throw failure;
    current = ScanDriverState(
      isInitialized: current.isInitialized,
      isRunning: current.isRunning,
      torchAvailable: current.torchAvailable,
      torchOn: enabled,
      zoom: current.zoom,
    );
    notifyListeners();
  }

  @override
  Future<void> setZoomRatio(double ratio) async {
    commandLog.add('zoom:$ratio');
    final failure = zoomFailure;
    if (failure != null) throw failure;
    current = ScanDriverState(
      isInitialized: current.isInitialized,
      isRunning: current.isRunning,
      torchAvailable: current.torchAvailable,
      torchOn: current.torchOn,
      zoom: ScanZoomRange(
        minimum: current.zoom!.minimum,
        maximum: current.zoom!.maximum,
        current: ratio,
      ),
    );
    notifyListeners();
  }

  @override
  Future<Iterable<String?>> analyzeImage(String path) async {
    commandLog.add('analyze');
    final failure = analyzeFailure;
    if (failure != null) throw failure;
    final gate = analyzeGate;
    if (gate != null) return gate.future;
    return analyzedValues;
  }

  @override
  Future<void> close() async {
    commandLog.add('close');
    closeCalls += 1;
    await closeGate?.future;
    final failure = closeFailure;
    if (failure != null) throw failure;
    super.dispose();
  }
}

final class FakeScanGallerySource implements ScanGallerySource {
  final paths = Queue<String?>();
  ScanDriverException? failure;
  Completer<String?>? selectionGate;
  var calls = 0;

  @override
  Future<String?> selectImagePath() async {
    calls += 1;
    final selectedFailure = failure;
    if (selectedFailure != null) throw selectedFailure;
    final gate = selectionGate;
    if (gate != null) return gate.future;
    return paths.isEmpty ? null : paths.removeFirst();
  }
}

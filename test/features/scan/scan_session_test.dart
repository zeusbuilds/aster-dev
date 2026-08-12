import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/scan/data/services/scan_session.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scan_fakes.dart';

void main() {
  test('scan payload is bounded, trimmed, and redacted from diagnostics', () {
    final payload = ScanPayload.parse(
      '  bitcoin:bc1qexample  ',
      source: ScanCaptureSource.camera,
    );

    expect(payload.value, 'bitcoin:bc1qexample');
    expect(payload.toString(), 'ScanPayload(camera)');
    expect(payload.toString(), isNot(contains('bc1qexample')));
    expect(
      () => ScanPayload.parse(
        'lightning:invoice\u202e',
        source: ScanCaptureSource.camera,
      ),
      throwsA(isA<InvalidScanPayloadException>()),
    );
    expect(
      () => ScanPayload.parse(
        'x' * (ScanPayload.maximumCharacters + 1),
        source: ScanCaptureSource.gallery,
      ),
      throwsA(isA<InvalidScanPayloadException>()),
    );
  });

  testWidgets('camera follows view and application lifecycle exactly', (
    tester,
  ) async {
    final driver = FakeScanCameraDriver();
    final session = ManagedScanSession(driver, FakeScanGallerySource());

    await tester.pumpWidget(_cameraApp(session));
    await tester.pump();
    expect(driver.commandLog, ['start']);
    expect(session.snapshot.isReady, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.idle();
    expect(driver.commandLog, ['start', 'stop']);
    expect(session.snapshot.isRunning, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.idle();
    expect(driver.commandLog, ['start', 'stop', 'start']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.idle();
    expect(driver.commandLog, ['start', 'stop', 'start', 'stop']);
    expect(await session.close(), isA<AppSuccess<void>>());
  });

  testWidgets('replacement session inherits the current inactive lifecycle', (
    tester,
  ) async {
    final firstDriver = FakeScanCameraDriver();
    final first = ManagedScanSession(firstDriver, FakeScanGallerySource());
    final secondDriver = FakeScanCameraDriver();
    final second = ManagedScanSession(secondDriver, FakeScanGallerySource());

    await tester.pumpWidget(_cameraApp(first));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.idle();
    await tester.pumpWidget(_cameraApp(second));
    await tester.pump();

    expect(secondDriver.commandLog, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.idle();
    expect(secondDriver.commandLog, ['start']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.idle();
    expect(await first.close(), isA<AppSuccess<void>>());
    expect(await second.close(), isA<AppSuccess<void>>());
  });

  testWidgets('replacement waits for prior native cleanup on a shared queue', (
    tester,
  ) async {
    final queue = ScanSessionCommandQueue();
    final firstDriver = FakeScanCameraDriver()..closeGate = Completer<void>();
    final secondDriver = FakeScanCameraDriver();
    final first = ManagedScanSession(
      firstDriver,
      FakeScanGallerySource(),
      commandQueue: queue,
    );
    final second = ManagedScanSession(
      secondDriver,
      FakeScanGallerySource(),
      commandQueue: queue,
    );

    await tester.pumpWidget(_cameraApp(first));
    await tester.pump();
    expect(firstDriver.commandLog, ['start']);

    final closing = first.close();
    await tester.pumpWidget(_cameraApp(second));
    await tester.pump();

    expect(firstDriver.commandLog, ['start', 'stop', 'close']);
    expect(secondDriver.commandLog, isEmpty);

    firstDriver.closeGate!.complete();
    expect(await closing, isA<AppSuccess<void>>());
    await tester.idle();
    expect(secondDriver.commandLog, ['start']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.idle();
    expect(await second.close(), isA<AppSuccess<void>>());
  });

  testWidgets('camera accepts one payload until explicitly re-armed', (
    tester,
  ) async {
    final driver = FakeScanCameraDriver();
    final session = ManagedScanSession(driver, FakeScanGallerySource());
    final captures = <ScanPayload>[];

    await tester.pumpWidget(_cameraApp(session, onCaptured: captures.add));
    await tester.pump();
    driver.emit(['first']);
    driver.emit(['second']);
    await tester.pump();

    expect(captures.map((value) => value.value), ['first']);
    expect(session.snapshot.captureLocked, isTrue);
    expect(driver.commandLog.where((value) => value == 'stop'), hasLength(1));

    session.resetCapture();
    expect(session.snapshot.captureLocked, isFalse);
    await session.setActive(true);
    driver.emit(['second']);
    await tester.pump();
    expect(captures.map((value) => value.value), ['first', 'second']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.idle();
    expect(await session.close(), isA<AppSuccess<void>>());
  });

  testWidgets('late driver failure cannot replace a committed capture', (
    tester,
  ) async {
    final driver = FakeScanCameraDriver();
    final session = ManagedScanSession(driver, FakeScanGallerySource());
    final captures = <ScanPayload>[];

    await tester.pumpWidget(_cameraApp(session, onCaptured: captures.add));
    await tester.pump();
    driver.emit(['bitcoin:bc1qaccepted']);
    driver.emitFailure(
      const ScanDriverException(
        code: 'scan_detection_failed',
        kind: ScanDriverFailureKind.unavailable,
      ),
    );
    await tester.idle();

    expect(captures, hasLength(1));
    expect(session.snapshot.captureLocked, isTrue);
    expect(session.snapshot.failure, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.idle();
    expect(await session.close(), isA<AppSuccess<void>>());
  });

  testWidgets('torch failure remains transient while camera stays active', (
    tester,
  ) async {
    final driver = FakeScanCameraDriver();
    final session = ManagedScanSession(driver, FakeScanGallerySource());

    await tester.pumpWidget(_cameraApp(session));
    await tester.pump();
    driver.torchFailure = const ScanDriverException(
      code: 'scan_torch_failed',
      kind: ScanDriverFailureKind.unavailable,
    );

    final result = await session.setTorchEnabled(true);

    expect(
      result,
      isA<AppFailureResult<void>>().having(
        (value) => value.failure.userMessage,
        'message',
        'The flashlight could not be changed.',
      ),
    );
    expect(session.snapshot.failure, isNull);
    expect(session.snapshot.isRunning, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.idle();
    expect(await session.close(), isA<AppSuccess<void>>());
  });

  testWidgets('unsafe camera payload fails closed and stops detection', (
    tester,
  ) async {
    final driver = FakeScanCameraDriver();
    final session = ManagedScanSession(driver, FakeScanGallerySource());
    final captures = <ScanPayload>[];

    await tester.pumpWidget(_cameraApp(session, onCaptured: captures.add));
    await tester.pump();
    driver.emit(['lightning:invoice\u202e']);
    await tester.idle();

    expect(captures, isEmpty);
    expect(session.snapshot.failure?.code, 'scan_payload_invalid');
    expect(session.snapshot.failure?.retryable, isFalse);
    expect(session.snapshot.captureLocked, isTrue);
    expect(driver.commandLog, ['start', 'stop']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.idle();
    expect(await session.close(), isA<AppSuccess<void>>());
  });

  testWidgets('driver detection failures lock and stop the active camera', (
    tester,
  ) async {
    final driver = FakeScanCameraDriver();
    final gallery = FakeScanGallerySource()..paths.add('payment-code');
    final session = ManagedScanSession(driver, gallery);

    await tester.pumpWidget(_cameraApp(session));
    await tester.pump();
    driver.emitFailure(
      const ScanDriverException(
        code: 'scan_detection_failed',
        kind: ScanDriverFailureKind.unavailable,
      ),
    );
    await tester.idle();

    expect(session.snapshot.captureLocked, isTrue);
    expect(session.snapshot.failure?.code, 'scan_detection_failed');
    expect(driver.commandLog, ['start', 'stop']);

    driver.analyzedValues = const ['bitcoin:bc1qgallery'];
    expect(
      await session.pickAndAnalyzeGallery(),
      isA<AppSuccess<ScanGalleryOutcome>>().having(
        (result) => (result.value as ScanGalleryCaptured).payload.value,
        'gallery payload',
        'bitcoin:bc1qgallery',
      ),
    );
    expect(session.snapshot.failure, isNull);
    expect(session.snapshot.captureLocked, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.idle();
    expect(await session.close(), isA<AppSuccess<void>>());
  });

  testWidgets('detections racing a requested pause are ignored', (
    tester,
  ) async {
    final driver = FakeScanCameraDriver();
    final session = ManagedScanSession(driver, FakeScanGallerySource());
    final captures = <ScanPayload>[];

    await tester.pumpWidget(_cameraApp(session, onCaptured: captures.add));
    await tester.pump();
    final paused = session.setActive(false);
    driver.emit(['bitcoin:bc1qlate']);
    await paused;
    await tester.idle();

    expect(captures, isEmpty);
    expect(session.snapshot.captureLocked, isFalse);
    expect(driver.commandLog, ['start', 'stop']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.idle();
    expect(await session.close(), isA<AppSuccess<void>>());
  });

  testWidgets('distinct simultaneous camera payloads fail closed', (
    tester,
  ) async {
    final driver = FakeScanCameraDriver();
    final session = ManagedScanSession(driver, FakeScanGallerySource());
    final captures = <ScanPayload>[];

    await tester.pumpWidget(_cameraApp(session, onCaptured: captures.add));
    await tester.pump();
    driver.emit(['first', 'second', 'first']);
    await tester.idle();

    expect(captures, isEmpty);
    expect(session.snapshot.failure?.code, 'scan_payload_ambiguous');
    expect(session.snapshot.failure?.retryable, isTrue);
    expect(session.snapshot.captureLocked, isTrue);
    expect(driver.commandLog, ['start', 'stop']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.idle();
    expect(await session.close(), isA<AppSuccess<void>>());
  });

  test('gallery distinguishes cancel, no-code, capture, and failure', () async {
    final driver = FakeScanCameraDriver();
    final gallery = FakeScanGallerySource()
      ..paths.addAll([null, 'one', 'ambiguous', 'two']);
    final session = ManagedScanSession(driver, gallery);

    expect(
      await session.pickAndAnalyzeGallery(),
      const AppResult<ScanGalleryOutcome>.success(ScanGalleryCancelled()),
    );

    driver.analyzedValues = const [];
    expect(
      await session.pickAndAnalyzeGallery(),
      const AppResult<ScanGalleryOutcome>.success(ScanGalleryNoCode()),
    );

    driver.analyzedValues = const ['first', 'second', 'first'];
    expect(
      await session.pickAndAnalyzeGallery(),
      isA<AppFailureResult<ScanGalleryOutcome>>().having(
        (value) => value.failure.code,
        'code',
        'scan_payload_ambiguous',
      ),
    );

    driver.analyzedValues = const ['lightning:invoice'];
    final captured = await session.pickAndAnalyzeGallery();
    expect(captured, isA<AppSuccess<ScanGalleryOutcome>>());
    expect(
      (captured as AppSuccess<ScanGalleryOutcome>).value,
      isA<ScanGalleryCaptured>().having(
        (value) => value.payload.value,
        'payload',
        'lightning:invoice',
      ),
    );

    session.resetCapture();
    gallery.paths.add('three');
    driver.analyzeFailure = const ScanDriverException(
      code: 'scan_gallery_unsupported',
      kind: ScanDriverFailureKind.unsupported,
    );
    final failed = await session.pickAndAnalyzeGallery();
    expect(
      failed,
      isA<AppFailureResult<ScanGalleryOutcome>>().having(
        (result) => result.failure.kind,
        'kind',
        AppFailureKind.unsupported,
      ),
    );
    expect(session.snapshot.failure, isNull);
    expect(await session.close(), isA<AppSuccess<void>>());
  });

  testWidgets('close drains an in-flight start before stop and disposal', (
    tester,
  ) async {
    final driver = FakeScanCameraDriver()..startGate = Completer<void>();
    final session = ManagedScanSession(driver, FakeScanGallerySource());

    await tester.pumpWidget(_cameraApp(session));
    await tester.pump();
    expect(driver.commandLog, ['start']);

    final closing = session.close();
    driver.startGate!.complete();
    expect(await closing, isA<AppSuccess<void>>());

    expect(driver.commandLog, ['start', 'stop', 'close']);
    expect(driver.closeCalls, 1);
    expect(await session.close(), isA<AppSuccess<void>>());
    expect(driver.closeCalls, 1);
  });

  test(
    'overlapping gallery selection fails without opening two pickers',
    () async {
      final driver = FakeScanCameraDriver();
      final gallery = FakeScanGallerySource()
        ..selectionGate = Completer<String?>();
      final session = ManagedScanSession(driver, gallery);

      final first = session.pickAndAnalyzeGallery();
      final second = await session.pickAndAnalyzeGallery();

      expect(
        second,
        isA<AppFailureResult<ScanGalleryOutcome>>().having(
          (value) => value.failure.code,
          'code',
          'scan_operation_unavailable',
        ),
      );
      expect(gallery.calls, 1);
      gallery.selectionGate!.complete();
      expect(
        await first,
        isA<AppSuccess<ScanGalleryOutcome>>().having(
          (value) => value.value,
          'outcome',
          isA<ScanGalleryCancelled>(),
        ),
      );
      expect(await session.close(), isA<AppSuccess<void>>());
    },
  );

  test('close drains an open gallery picker before driver disposal', () async {
    final driver = FakeScanCameraDriver();
    final gallery = FakeScanGallerySource()
      ..selectionGate = Completer<String?>();
    final session = ManagedScanSession(driver, gallery);

    final picking = session.pickAndAnalyzeGallery();
    final closing = session.close();

    expect(driver.closeCalls, 0);
    gallery.selectionGate!.complete('selected-image');
    expect(
      await picking,
      isA<AppFailureResult<ScanGalleryOutcome>>().having(
        (value) => value.failure.code,
        'code',
        'scan_operation_unavailable',
      ),
    );
    expect(await closing, isA<AppSuccess<void>>());
    expect(driver.commandLog, ['close']);
    expect(driver.closeCalls, 1);
  });

  test('close still disposes the driver when stopping fails', () async {
    final driver = FakeScanCameraDriver()
      ..current = const ScanDriverState(
        isInitialized: true,
        isRunning: true,
        torchAvailable: true,
      )
      ..stopFailure = const ScanDriverException(
        code: 'scan_camera_stop_failed',
        kind: ScanDriverFailureKind.unavailable,
      );
    final session = ManagedScanSession(driver, FakeScanGallerySource());

    final result = await session.close();

    expect(
      result,
      isA<AppFailureResult<void>>().having(
        (value) => value.failure.code,
        'code',
        'scan_camera_cleanup_failed',
      ),
    );
    expect(driver.commandLog, ['stop', 'close']);
    expect(driver.closeCalls, 1);
  });

  test('close reports controller disposal failure without throwing', () async {
    final driver = FakeScanCameraDriver()
      ..closeFailure = const ScanDriverException(
        code: 'scan_camera_dispose_failed',
        kind: ScanDriverFailureKind.unavailable,
      );
    final session = ManagedScanSession(driver, FakeScanGallerySource());

    final result = await session.close();

    expect(
      result,
      isA<AppFailureResult<void>>().having(
        (value) => value.failure.code,
        'code',
        'scan_camera_cleanup_failed',
      ),
    );
    expect(driver.commandLog, ['close']);
    expect(driver.closeCalls, 1);
  });
}

Widget _cameraApp(
  ScanSession session, {
  ValueChanged<ScanPayload>? onCaptured,
}) {
  return MaterialApp(
    home: session.buildCameraSurface(
      scanWindow: const Rect.fromLTWH(20, 20, 100, 100),
      placeholderColor: Colors.black,
      onCaptured: onCaptured ?? (_) {},
    ),
  );
}

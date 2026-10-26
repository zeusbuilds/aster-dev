import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/scan/data/services/services.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:aster/features/scan/presentation/models/models.dart';
import 'package:aster/features/scan/presentation/view_model/view_models.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/presentation_fakes.dart';
import '../../support/scan_fakes.dart';

void main() {
  test(
    'camera commands follow real capabilities and emit semantic haptics',
    () async {
      final session = FakeScanSession();
      final haptics = RecordingHapticFeedbackService();
      final container = ProviderContainer(
        overrides: [
          scanSessionProvider(ScanPurpose.sendLauncher)
              .overrideWithValue(session),
          hapticFeedbackServiceProvider.overrideWithValue(haptics),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        scanViewModelProvider(ScanPurpose.sendLauncher),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final viewModel = container.read(
        scanViewModelProvider(ScanPurpose.sendLauncher).notifier,
      );

      expect(await viewModel.toggleFlash(), isA<AppSuccess<void>>());
      expect(session.torchValues, [true]);
      expect(await viewModel.cycleZoom(), isA<AppSuccess<void>>());
      expect(session.zoomValues, [ScanZoomPreset.closer.scale]);
      expect(haptics.intents, [HapticIntent.selection, HapticIntent.selection]);

      session.replaceSnapshot(session.current.copyWith(zoomScale: 1));
      expect(
        container
            .read(scanViewModelProvider(ScanPurpose.sendLauncher))
            .zoomPreset,
        ScanZoomPreset.closest,
      );

      session.replaceSnapshot(
        const ScanSessionSnapshot(
          isInitialized: true,
          isRunning: true,
          torchAvailable: false,
        ),
      );
      expect(await viewModel.toggleFlash(), isA<AppFailureResult<void>>());
      expect(session.torchValues, [true]);
    },
  );

  test(
    'control failure is transient and does not poison camera state',
    () async {
      final session = FakeScanSession()
        ..torchResult = AppResult.failure(
          const AppFailure(
            code: 'scan_torch_failed',
            kind: AppFailureKind.unavailable,
            userMessage: 'The flashlight could not be changed.',
            retryable: true,
          ),
        );
      final haptics = RecordingHapticFeedbackService();
      final container = ProviderContainer(
        overrides: [
          scanSessionProvider(ScanPurpose.sendLauncher)
              .overrideWithValue(session),
          hapticFeedbackServiceProvider.overrideWithValue(haptics),
        ],
      );
      addTearDown(container.dispose);
      final provider = scanViewModelProvider(ScanPurpose.sendLauncher);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final result = await container.read(provider.notifier).toggleFlash();

      expect(result, isA<AppFailureResult<void>>());
      expect(container.read(provider).failure, isNull);
      expect(container.read(provider).cameraReady, isTrue);
      expect(container.read(provider).operation, isNull);
      expect(haptics.intents, [HapticIntent.error]);
    },
  );

  test(
    'zoom display follows the native applied scale, not the request',
    () async {
      final session = FakeScanSession()
        ..current = const ScanSessionSnapshot(
          isInitialized: true,
          isRunning: true,
          torchAvailable: true,
          zoomScale: 0.5,
        )
        ..reportedZoomScale = 0.5;
      final container = ProviderContainer(
        overrides: [
          scanSessionProvider(ScanPurpose.sendLauncher)
              .overrideWithValue(session),
          hapticFeedbackServiceProvider.overrideWithValue(
            RecordingHapticFeedbackService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = scanViewModelProvider(ScanPurpose.sendLauncher);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      expect(
        await container.read(provider.notifier).cycleZoom(),
        isA<AppSuccess<void>>(),
      );

      expect(session.zoomValues, [1]);
      expect(container.read(provider).zoomPreset, ScanZoomPreset.closer);
    },
  );

  test(
    'capture lock suppresses duplicates and is re-armed after navigation',
    () async {
      final session = FakeScanSession();
      final haptics = RecordingHapticFeedbackService();
      final container = ProviderContainer(
        overrides: [
          scanSessionProvider(ScanPurpose.destinationPicker)
              .overrideWithValue(session),
          hapticFeedbackServiceProvider.overrideWithValue(haptics),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        scanViewModelProvider(ScanPurpose.destinationPicker),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final viewModel = container.read(
        scanViewModelProvider(ScanPurpose.destinationPicker).notifier,
      );
      final first = ScanPayload.parse(
        'first',
        source: ScanCaptureSource.camera,
      );
      final second = ScanPayload.parse(
        'second',
        source: ScanCaptureSource.camera,
      );

      expect(viewModel.acceptCameraPayload(first), isTrue);
      expect(viewModel.acceptCameraPayload(second), isFalse);
      expect(haptics.intents, [HapticIntent.lightImpact]);

      await viewModel.resumeAfterNavigation();
      expect(session.resetCaptureCalls, 1);
      expect(session.activeValues.last, isTrue);
      expect(viewModel.acceptCameraPayload(second), isTrue);
    },
  );

  test(
    'gallery preserves cancel/no-code/failure semantics without camera failure',
    () async {
      final session = FakeScanSession();
      final haptics = RecordingHapticFeedbackService();
      final container = ProviderContainer(
        overrides: [
          scanSessionProvider(ScanPurpose.sendLauncher)
              .overrideWithValue(session),
          hapticFeedbackServiceProvider.overrideWithValue(haptics),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        scanViewModelProvider(ScanPurpose.sendLauncher),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final provider = scanViewModelProvider(ScanPurpose.sendLauncher);
      final viewModel = container.read(provider.notifier);

      session.galleryResult = const AppResult.success(ScanGalleryNoCode());
      expect(
        await viewModel.scanGallery(),
        isA<AppSuccess<ScanGalleryOutcome>>(),
      );
      expect(haptics.intents, [HapticIntent.warning]);
      expect(container.read(provider).failure, isNull);

      session.galleryResult = AppResult.failure(
        const AppFailure(
          code: 'scan_gallery_unsupported',
          kind: AppFailureKind.unsupported,
          userMessage: 'Image scanning is unsupported.',
          retryable: false,
        ),
      );
      expect(
        await viewModel.scanGallery(),
        isA<AppFailureResult<ScanGalleryOutcome>>(),
      );
      expect(haptics.intents.last, HapticIntent.warning);
      expect(container.read(provider).failure, isNull);
    },
  );

  test('camera failures are persistent, redacted, and haptic once', () async {
    final session = FakeScanSession();
    final haptics = RecordingHapticFeedbackService();
    final container = ProviderContainer(
      overrides: [
        scanSessionProvider(ScanPurpose.sendLauncher)
            .overrideWithValue(session),
        hapticFeedbackServiceProvider.overrideWithValue(haptics),
      ],
    );
    addTearDown(container.dispose);
    final provider = scanViewModelProvider(ScanPurpose.sendLauncher);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    const failure = AppFailure(
      code: 'scan_camera_permission_denied',
      kind: AppFailureKind.authentication,
      userMessage: 'Allow camera access in system settings to scan a code.',
      retryable: false,
    );

    session.replaceSnapshot(session.current.copyWith(failure: failure));
    session.replaceSnapshot(session.current.copyWith(failure: failure));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(provider).failure, failure);
    expect(haptics.intents, [HapticIntent.warning]);
    expect(failure.toString(), isNot(contains('system settings')));

    session.galleryResult = const AppResult.success(ScanGalleryCancelled());
    await container.read(provider.notifier).scanGallery();
    expect(container.read(provider).failure, failure);
    expect(haptics.intents, [HapticIntent.warning]);
  });

  test('camera failure leaves gallery and manual fallbacks available', () {
    const failure = AppFailure(
      code: 'scan_camera_permission_denied',
      kind: AppFailureKind.authentication,
      userMessage: 'Allow camera access.',
      retryable: false,
    );
    const state = ScanState(captureLocked: true, failure: failure);

    expect(state.canUseGallery, isTrue);
    expect(state.canEnterManually, isTrue);
    expect(state.hasCommittedCapture, isFalse);
  });

  test('camera capture supersedes an in-flight control operation', () async {
    final session = FakeScanSession()..torchGate = Completer<AppResult<void>>();
    final haptics = RecordingHapticFeedbackService();
    final container = ProviderContainer(
      overrides: [
        scanSessionProvider(ScanPurpose.sendLauncher)
            .overrideWithValue(session),
        hapticFeedbackServiceProvider.overrideWithValue(haptics),
      ],
    );
    addTearDown(container.dispose);
    final provider = scanViewModelProvider(ScanPurpose.sendLauncher);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final viewModel = container.read(provider.notifier);

    final toggle = viewModel.toggleFlash();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).operation, ScanOperation.togglingTorch);

    final accepted = viewModel.acceptCameraPayload(
      ScanPayload.parse(
        'bitcoin:bc1qcaptured',
        source: ScanCaptureSource.camera,
      ),
    );
    expect(accepted, isTrue);
    expect(container.read(provider).captureLocked, isTrue);
    expect(container.read(provider).operation, isNull);

    session.current = session.current.copyWith(captureLocked: true);
    session.torchGate!.complete(const AppResult.success(null));
    expect(
      await toggle,
      isA<AppFailureResult<void>>().having(
        (value) => value.failure.code,
        'code',
        'scan_operation_unavailable',
      ),
    );
    expect(container.read(provider).captureLocked, isTrue);
    expect(container.read(provider).operation, isNull);
    expect(haptics.intents, [HapticIntent.lightImpact]);
  });

  test('session factory creates separate tab and picker owners', () {
    final tab = FakeScanSession();
    final picker = FakeScanSession();
    final container = ProviderContainer(
      overrides: [
        scanSessionFactoryProvider.overrideWithValue(
          QueueScanSessionFactory([tab, picker]),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(scanSessionProvider(ScanPurpose.sendLauncher)), tab);
    expect(
      container.read(scanSessionProvider(ScanPurpose.destinationPicker)),
      picker,
    );
  });

  test(
    'rebuild transfers exactly one listener to the current session',
    () async {
      final first = FakeScanSession();
      final second = FakeScanSession();
      var session = first;
      final purpose = ScanPurpose.sendLauncher;
      final container = ProviderContainer(
        overrides: [
          scanSessionProvider(purpose).overrideWith((ref) => session),
          hapticFeedbackServiceProvider.overrideWithValue(
            RecordingHapticFeedbackService(),
          ),
        ],
      );
      final provider = scanViewModelProvider(purpose);
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      expect(first.listenerCount, 1);

      session = second;
      container.invalidate(scanSessionProvider(purpose));
      await _waitFor(
        () => first.listenerCount == 0 && second.listenerCount == 1,
      );

      expect(first.listenerCount, 0);
      expect(second.listenerCount, 1);
      subscription.close();
      container.dispose();
      expect(second.listenerCount, 0);
    },
  );

  test('session replacement suppresses an obsolete gallery capture', () async {
    final first = FakeScanSession()
      ..galleryGate = Completer<AppResult<ScanGalleryOutcome>>();
    final second = FakeScanSession();
    var session = first;
    final purpose = ScanPurpose.sendLauncher;
    final haptics = RecordingHapticFeedbackService();
    final container = ProviderContainer(
      overrides: [
        scanSessionProvider(purpose).overrideWith((ref) => session),
        hapticFeedbackServiceProvider.overrideWithValue(haptics),
      ],
    );
    addTearDown(container.dispose);
    final provider = scanViewModelProvider(purpose);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final gallery = container.read(provider.notifier).scanGallery();
    await Future<void>.delayed(Duration.zero);
    session = second;
    container.invalidate(scanSessionProvider(purpose));
    await _waitFor(() => first.listenerCount == 0 && second.listenerCount == 1);
    first.replaceSnapshot(
      first.current.copyWith(galleryPhase: ScanGalleryPhase.analyzing),
    );
    expect(container.read(provider).galleryPhase, ScanGalleryPhase.idle);
    expect(container.read(provider).galleryAnalyzing, isFalse);
    first.galleryGate!.complete(
      AppResult.success(
        ScanGalleryCaptured(
          ScanPayload.parse(
            'lightning:obsolete',
            source: ScanCaptureSource.gallery,
          ),
        ),
      ),
    );

    expect(
      await gallery,
      isA<AppFailureResult<ScanGalleryOutcome>>().having(
        (value) => value.failure.code,
        'code',
        'scan_operation_unavailable',
      ),
    );
    expect(container.read(provider).captureLocked, isFalse);
    expect(haptics.intents, isEmpty);
  });

  test('session replacement invalidates native command completions', () async {
    final first = FakeScanSession();
    final second = FakeScanSession();
    var session = first;
    final purpose = ScanPurpose.sendLauncher;
    final container = ProviderContainer(
      overrides: [
        scanSessionProvider(purpose).overrideWith((ref) => session),
        hapticFeedbackServiceProvider.overrideWithValue(
          RecordingHapticFeedbackService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final provider = scanViewModelProvider(purpose);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    first.activeGate = Completer<AppResult<void>>();
    final paused = container.read(provider.notifier).pauseForNavigation();
    await Future<void>.delayed(Duration.zero);
    session = second;
    container.invalidate(scanSessionProvider(purpose));
    await _waitFor(() => first.listenerCount == 0 && second.listenerCount == 1);
    first.activeGate!.complete(const AppResult.success(null));
    expect(
      await paused,
      isA<AppFailureResult<void>>().having(
        (value) => value.failure.code,
        'code',
        'scan_operation_unavailable',
      ),
    );

    second.current = second.current.copyWith(
      failure: const AppFailure(
        code: 'scan_camera_failed',
        kind: AppFailureKind.unavailable,
        userMessage: 'The camera could not be started.',
        retryable: true,
      ),
    );
    second.replaceSnapshot(second.current);
    second.restartGate = Completer<AppResult<void>>();
    final restarted = container.read(provider.notifier).retryCamera();
    await Future<void>.delayed(Duration.zero);
    final third = FakeScanSession();
    session = third;
    container.invalidate(scanSessionProvider(purpose));
    await _waitFor(() => second.listenerCount == 0 && third.listenerCount == 1);
    second.restartGate!.complete(const AppResult.success(null));
    expect(await restarted, isFalse);
    expect(container.read(provider).failure, isNull);
  });

  test('navigation pause blocks controls and reports stop failure', () async {
    final session = FakeScanSession();
    final haptics = RecordingHapticFeedbackService();
    final container = ProviderContainer(
      overrides: [
        scanSessionProvider(ScanPurpose.sendLauncher)
            .overrideWithValue(session),
        hapticFeedbackServiceProvider.overrideWithValue(haptics),
      ],
    );
    addTearDown(container.dispose);
    final provider = scanViewModelProvider(ScanPurpose.sendLauncher);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final viewModel = container.read(provider.notifier);

    final paused = await viewModel.pauseForNavigation();

    expect(paused, isA<AppSuccess<void>>());
    expect(container.read(provider).isBusy, isTrue);
    expect(container.read(provider).canUseGallery, isFalse);
    await viewModel.resumeAfterNavigation();
    expect(container.read(provider).isBusy, isFalse);

    session.activeResult = AppResult.failure(
      const AppFailure(
        code: 'scan_camera_stop_failed',
        kind: AppFailureKind.unavailable,
        userMessage: 'The camera could not be stopped.',
        retryable: true,
      ),
    );
    final failed = await viewModel.pauseForNavigation();

    expect(failed, isA<AppFailureResult<void>>());
    expect(container.read(provider).isBusy, isFalse);
    expect(container.read(provider).failure?.code, 'scan_camera_stop_failed');
    expect(haptics.intents.last, HapticIntent.error);
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for Scan session ownership.');
}

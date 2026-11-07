import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/scan/data/services/services.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:aster/features/scan/presentation/view_model/view_models.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/presentation_fakes.dart';
import '../../support/scan_fakes.dart';

void main() {
  final provider = scanViewModelProvider(ScanPurpose.sendLauncher);

  ProviderContainer containerFor(FakeScanSession session) {
    final container = ProviderContainer(
      overrides: [
        scanSessionProvider(ScanPurpose.sendLauncher)
            .overrideWithValue(session),
        hapticFeedbackServiceProvider.overrideWithValue(
          RecordingHapticFeedbackService(),
        ),
      ],
    );
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    return container;
  }

  test(
    '1x 2x 3x are actual requests rather than normalized camera maximum',
    () async {
      final session = FakeScanSession()
        ..current = const ScanSessionSnapshot(
          isInitialized: true,
          isRunning: true,
          zoom: ScanZoomRange(minimum: 1, maximum: 10, current: 1),
        );
      final container = containerFor(session);
      final viewModel = container.read(provider.notifier);

      for (final label in ['2x', '3x', '1x']) {
        expect(await viewModel.cycleZoom(), isA<AppSuccess<void>>());
        expect(container.read(provider).zoom?.displayLabel, label);
      }
      expect(session.zoomValues, [2, 3, 1]);
    },
  );

  test(
    '2x camera cycles back to 1x without requesting unsupported 3x',
    () async {
      final session = FakeScanSession()
        ..current = const ScanSessionSnapshot(
          isInitialized: true,
          isRunning: true,
          zoom: ScanZoomRange(minimum: 1, maximum: 2, current: 1),
        );
      final container = containerFor(session);
      final viewModel = container.read(provider.notifier);

      await viewModel.cycleZoom();
      await viewModel.cycleZoom();

      expect(session.zoomValues, [2, 1]);
      expect(container.read(provider).zoom?.displayLabel, '1x');
    },
  );

  test(
    'unknown and fixed camera zoom cannot send a magnification command',
    () async {
      final session = FakeScanSession()
        ..current = const ScanSessionSnapshot(
          isInitialized: true,
          isRunning: true,
        );
      final container = containerFor(session);
      final viewModel = container.read(provider.notifier);

      expect(container.read(provider).zoom, isNull);
      expect(container.read(provider).canChangeZoom, isFalse);
      expect(await viewModel.cycleZoom(), isA<AppFailureResult<void>>());
      session.replaceSnapshot(
        session.current.copyWith(
          zoom: const ScanZoomRange(minimum: 1, maximum: 1, current: 1),
        ),
      );
      expect(container.read(provider).zoom?.displayLabel, '1x');
      expect(container.read(provider).canChangeZoom, isFalse);
      expect(await viewModel.cycleZoom(), isA<AppFailureResult<void>>());
      expect(session.zoomValues, isEmpty);
    },
  );

  test(
    'pending zoom retains confirmed value and quietly guards duplicate taps',
    () async {
      final session = FakeScanSession()
        ..zoomGate = Completer<AppResult<void>>();
      final container = containerFor(session);
      final viewModel = container.read(provider.notifier);

      final pending = viewModel.cycleZoom();
      expect(container.read(provider).zoom?.displayLabel, '1x');
      expect(container.read(provider).canChangeZoom, isFalse);
      expect(await viewModel.cycleZoom(), isA<AppFailureResult<void>>());
      expect(session.zoomValues, [2]);
      session.zoomGate!.complete(const AppResult.success(null));
      expect(await pending, isA<AppSuccess<void>>());
      expect(container.read(provider).zoom?.displayLabel, '2x');
    },
  );

  test('failed magnification leaves confirmed label and camera usable without message', () async {
    final session = FakeScanSession()
      ..zoomResult = const AppResult.failure(
        AppFailure(
          code: 'scan_zoom_failed',
          kind: AppFailureKind.unavailable,
          userMessage: 'The zoom could not be changed.',
          retryable: true,
        ),
      );
    final container = containerFor(session);

    expect(
      await container.read(provider.notifier).cycleZoom(),
      isA<AppFailureResult<void>>(),
    );

    final state = container.read(provider);
    expect(state.zoom?.displayLabel, '1x');
    expect(state.failure, isNull);
    expect(state.cameraReady, isTrue);
    expect(state.canChangeZoom, isTrue);
    expect(state.isBusy, isFalse);
  });

  test(
    'a late zoom result cannot restore capabilities after camera suspension',
    () async {
      final session = FakeScanSession()
        ..zoomGate = Completer<AppResult<void>>();
      final container = containerFor(session);

      final pending = container.read(provider.notifier).cycleZoom();
      session.replaceSnapshot(
        session.current.copyWith(isRunning: false, zoom: null),
      );
      session.zoomGate!.complete(const AppResult.success(null));
      await pending;

      expect(container.read(provider).zoom, isNull);
      expect(container.read(provider).canChangeZoom, isFalse);
      expect(container.read(provider).cameraReady, isFalse);
    },
  );
}

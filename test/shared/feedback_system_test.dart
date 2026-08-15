import 'dart:async';

import 'package:aster/shared/shared.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformHapticFeedbackService', () {
    test('shares one capability probe across concurrent intents', () async {
      final capability = Completer<bool>();
      var probeCount = 0;
      final emitted = <HapticIntent>[];
      final service = PlatformHapticFeedbackService(
        capabilityProbe: () {
          probeCount += 1;
          return capability.future;
        },
        emitter: (intent) async => emitted.add(intent),
      );

      final first = service.trigger(HapticIntent.selection);
      final second = service.trigger(HapticIntent.error);
      expect(probeCount, 1);

      capability.complete(true);
      await Future.wait([first, second]);

      expect(probeCount, 1);
      expect(emitted, [HapticIntent.selection, HapticIntent.error]);
    });

    test('caches an unsupported or failed capability probe', () async {
      var probeCount = 0;
      var emitCount = 0;
      final service = PlatformHapticFeedbackService(
        capabilityProbe: () async {
          probeCount += 1;
          throw StateError('platform unavailable');
        },
        emitter: (_) async => emitCount += 1,
      );

      await service.trigger(HapticIntent.lightImpact);
      await service.trigger(HapticIntent.success);

      expect(probeCount, 1);
      expect(emitCount, 0);
    });

    test('never forwards emitter failures to the user action', () async {
      final service = PlatformHapticFeedbackService(
        capabilityProbe: () async => true,
        emitter: (_) async => throw StateError('device failure'),
      );

      await expectLater(service.trigger(HapticIntent.commit), completes);
    });
  });

  group('ToastController', () {
    late ProviderContainer container;
    late ToastController controller;

    setUp(() {
      container = ProviderContainer();
      controller = container.read(toastControllerProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('queue state defensively owns pending messages', () {
      const message = ToastMessage(
        id: 1,
        title: 'Owned',
        variant: ToastVariant.info,
        duration: Duration(seconds: 1),
      );
      final source = <ToastMessage>[message];
      final state = ToastQueueState(pending: source);

      source.clear();
      expect(state.pending, [message]);
      expect(() => state.pending.clear(), throwsUnsupportedError);
    });

    test('message and queue values compare by complete content', () {
      final currentA = ToastMessage(
        id: 1,
        title: 'Current',
        message: 'Details',
        variant: ToastVariant.info,
        duration: const Duration(seconds: 2),
      );
      final currentB = ToastMessage(
        id: 1,
        title: 'Current',
        message: 'Details',
        variant: ToastVariant.info,
        duration: const Duration(seconds: 2),
      );
      final pendingA = ToastMessage(
        id: 2,
        title: 'Pending',
        variant: ToastVariant.warning,
        duration: const Duration(seconds: 3),
      );
      final pendingB = ToastMessage(
        id: 2,
        title: 'Pending',
        variant: ToastVariant.warning,
        duration: const Duration(seconds: 3),
      );
      final stateA = ToastQueueState(current: currentA, pending: [pendingA]);
      final stateB = ToastQueueState(current: currentB, pending: [pendingB]);

      expect(currentA, currentB);
      expect(currentA.hashCode, currentB.hashCode);
      expect(stateA, stateB);
      expect(stateA.hashCode, stateB.hashCode);
      expect(
        currentA,
        isNot(
          ToastMessage(
            id: 1,
            title: 'Current',
            message: 'Details',
            variant: ToastVariant.info,
            duration: const Duration(seconds: 3),
          ),
        ),
      );
      expect(stateA, isNot(ToastQueueState(current: currentA)));
    });

    test('normalizes, deduplicates, bounds, and drains FIFO messages', () {
      expect(
        controller.show(
          title: '  First  ',
          message: '  Details  ',
          variant: ToastVariant.info,
        ),
        isTrue,
      );
      expect(
        controller.show(
          title: 'First',
          message: 'Details',
          variant: ToastVariant.info,
        ),
        isFalse,
      );

      for (
        var index = 2;
        index <= ToastController.maximumPendingMessages + 1;
        index += 1
      ) {
        expect(
          controller.show(
            title: 'Message $index',
            variant: ToastVariant.warning,
          ),
          isTrue,
        );
      }
      expect(
        controller.show(title: 'Overflow', variant: ToastVariant.failure),
        isFalse,
      );

      var state = container.read(toastControllerProvider);
      expect(state.current?.title, 'First');
      expect(state.current?.message, 'Details');
      expect(state.pending, hasLength(ToastController.maximumPendingMessages));
      expect(() => state.pending.add(state.current!), throwsUnsupportedError);

      controller.dismissCurrent(id: 999);
      expect(container.read(toastControllerProvider).current?.title, 'First');

      final observed = <String>[];
      while ((state = container.read(toastControllerProvider)).current !=
          null) {
        final current = state.current!;
        observed.add(current.title);
        controller.dismissCurrent(id: current.id);
      }
      expect(observed, [
        'First',
        'Message 2',
        'Message 3',
        'Message 4',
        'Message 5',
      ]);
    });

    test('rejects invalid text and visibility bounds', () {
      expect(controller.show(title: '  ', variant: ToastVariant.info), isFalse);
      expect(
        controller.show(
          title: List.filled(
            ToastController.maximumTitleCharacters + 1,
            'x',
          ).join(),
          variant: ToastVariant.info,
        ),
        isFalse,
      );
      expect(
        controller.show(
          title: 'Message',
          message: List.filled(
            ToastController.maximumMessageCharacters + 1,
            'x',
          ).join(),
          variant: ToastVariant.info,
        ),
        isFalse,
      );
      expect(
        controller.show(
          title: 'Message',
          variant: ToastVariant.info,
          duration: Duration.zero,
        ),
        isFalse,
      );
      expect(
        controller.show(
          title: 'Message',
          variant: ToastVariant.info,
          duration:
              ToastController.maximumVisibleDuration +
              const Duration(milliseconds: 1),
        ),
        isFalse,
      );
    });
  });
}

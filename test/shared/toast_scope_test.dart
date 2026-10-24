import 'dart:async';

import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'route change expires visible and queued messages and all old origins',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(toastControllerProvider.notifier);
      controller.updateRouteScope('/send');
      final origin = controller.captureOrigin();
      expect(
        origin.show(title: 'First', variant: ToastVariant.failure),
        isTrue,
      );
      expect(origin.show(title: 'Queued', variant: ToastVariant.info), isTrue);
      controller.updateRouteScope('/home');
      expect(container.read(toastControllerProvider).current, isNull);
      expect(container.read(toastControllerProvider).pending, isEmpty);
      expect(
        origin.show(title: 'Late result', variant: ToastVariant.failure),
        isFalse,
      );
      controller.updateRouteScope('/send');
      expect(
        origin.show(title: 'Earlier visit', variant: ToastVariant.failure),
        isFalse,
      );
      expect(
        controller.captureOrigin().show(
          title: 'New action',
          variant: ToastVariant.info,
        ),
        isTrue,
      );
      origin.dismissCurrent();
      expect(
        container.read(toastControllerProvider).current?.title,
        'New action',
      );
    },
  );

  test('wallet change expires messages while an unchanged identity preserves ownership', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(toastControllerProvider.notifier);
    controller.updateWalletScope('wallet-a');
    final origin = controller.captureOrigin();
    controller.updateWalletScope('wallet-a');
    expect(
      origin.show(title: 'Same wallet', variant: ToastVariant.info),
      isTrue,
    );
    controller.updateWalletScope('wallet-b');
    expect(container.read(toastControllerProvider).current, isNull);
    expect(
      origin.show(title: 'Old wallet', variant: ToastVariant.failure),
      isFalse,
    );
    controller.updateWalletScope('wallet-a');
    expect(
      origin.show(title: 'Old visit', variant: ToastVariant.failure),
      isFalse,
    );
  });

  test('a disposed controller cannot accept a late captured result', () {
    final container = ProviderContainer();
    final origin = container
        .read(toastControllerProvider.notifier)
        .captureOrigin();
    container.dispose();
    expect(
      origin.show(title: 'Late result', variant: ToastVariant.failure),
      isFalse,
    );
  });

  test('popup presentation changes retain the parent action origin', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(toastControllerProvider.notifier);
    controller.updateRouteScope('/send');
    controller.updateWalletScope('wallet-a');
    final origin = controller.captureOrigin();
    origin.show(title: 'Earlier feedback', variant: ToastVariant.info);
    origin.show(title: 'Queued feedback', variant: ToastVariant.warning);
    final generation = container.read(toastControllerProvider).scopeGeneration;

    controller.discardMessagesForPopup();

    final cleared = container.read(toastControllerProvider);
    expect(cleared.current, isNull);
    expect(cleared.pending, isEmpty);
    expect(cleared.scopeGeneration, greaterThan(generation));
    expect(
      origin.show(title: 'Confirmation result', variant: ToastVariant.info),
      isTrue,
    );
    controller.updateWalletScope('wallet-b');
    expect(
      origin.show(title: 'Wrong wallet result', variant: ToastVariant.failure),
      isFalse,
    );
  });

  testWidgets(
    'a still-mounted covered route cannot show late action feedback',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final toasts = container.read(toastControllerProvider.notifier);
      final completed = Completer<void>();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => AsterFeedbackScope(
            haptics: const NoopHapticFeedbackService(),
            toasts: toasts,
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final origin = context.toasts;
                  await completed.future;
                  origin.show(
                    title: 'Late covered result',
                    variant: ToastVariant.failure,
                  );
                },
                child: const Text('Start action'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start action'));
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      completed.complete();
      await tester.pump();
      expect(container.read(toastControllerProvider).current, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'captured context feedback rejects a late result after a wallet change',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final toasts = container.read(toastControllerProvider.notifier);
      toasts.updateWalletScope('wallet-a');
      final completed = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => AsterFeedbackScope(
            haptics: const NoopHapticFeedbackService(),
            toasts: toasts,
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final origin = context.toasts;
                  await completed.future;
                  origin.show(
                    title: 'Wrong wallet result',
                    variant: ToastVariant.failure,
                  );
                },
                child: const Text('Start action'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start action'));
      toasts.updateWalletScope('wallet-b');
      completed.complete();
      await tester.pump();
      expect(container.read(toastControllerProvider).current, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final alreadyDismissing in [false, true]) {
    testWidgets(
      'scope expiry removes old toast immediately (already dismissing: $alreadyDismissing)',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final controller = container.read(toastControllerProvider.notifier);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const ToastHost(child: Scaffold()),
            ),
          ),
        );
        controller.show(
          title: 'Old route feedback',
          variant: ToastVariant.failure,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Old route feedback'), findsOneWidget);
        if (alreadyDismissing) {
          controller.dismissCurrent();
          await tester.pump();
          expect(find.text('Old route feedback'), findsOneWidget);
        }
        controller.updateRouteScope('/new-route');
        await tester.pump();
        expect(find.text('Old route feedback'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'popup clears visible and outgoing feedback (already dismissing: $alreadyDismissing)',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final controller = container.read(toastControllerProvider.notifier);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const ToastHost(child: Scaffold()),
            ),
          ),
        );
        controller.show(
          title: 'Previous action',
          variant: ToastVariant.failure,
        );
        controller.show(
          title: 'Queued previous action',
          variant: ToastVariant.failure,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        if (alreadyDismissing) {
          controller.dismissCurrent();
          await tester.pump();
        }
        expect(find.text('Previous action'), findsOneWidget);

        controller.discardMessagesForPopup();
        await tester.pump();

        expect(find.text('Previous action'), findsNothing);
        expect(find.text('Queued previous action'), findsNothing);
        expect(container.read(toastControllerProvider).pending, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

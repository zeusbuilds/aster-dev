import 'dart:async';
import 'dart:collection';

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/pages/wallet_access_screen.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/presentation_fakes.dart';

void main() {
  testWidgets('wallet access keeps Retry visible while the registry reloads', (
    tester,
  ) async {
    final model = _RetryingWalletAccess();
    final container = ProviderContainer(
      retry: applicationProviderRetryPolicy,
      overrides: [walletViewModelProvider.overrideWith(() => model)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const WalletAccessScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Wallet access unavailable'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(
      tester.widget<CustomButton>(find.byType(CustomButton)).loading,
      true,
    );
    await tester.tap(find.byType(CustomButton), warnIfMissed: false);
    expect(model.attempts, 1);

    model.reloadComplete.complete();
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Local wallet data could not be verified.'),
      findsOneWidget,
    );
    expect(find.byType(CustomButton), findsNothing);
  });

  test(
    'serializes rapid lifecycle events without revealing stale UI',
    () async {
      final repository = _ControlledLifecycleRepository();
      final suspended = repository.enqueue('suspend');
      final resumed = repository.enqueue('resume');
      final container = _container(repository);
      addTearDown(container.dispose);
      final notifier = container.read(
        walletLifecycleViewModelProvider.notifier,
      );

      final suspendFuture = notifier.handle(AppLifecycleState.paused);
      final resumeFuture = notifier.handle(AppLifecycleState.resumed);
      expect(
        container.read(walletLifecycleViewModelProvider),
        const WalletLifecycleState(obscured: true, transitioning: true),
      );

      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, ['suspend']);
      suspended.complete(const AppResult.success(null));
      expect(await suspendFuture, isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(repository.calls, ['suspend', 'resume']);
      expect(
        container.read(walletLifecycleViewModelProvider).showsPrivacySplash,
        isTrue,
      );
      resumed.complete(const AppResult.success(null));
      expect(await resumeFuture, isTrue);

      expect(
        container.read(walletLifecycleViewModelProvider),
        const WalletLifecycleState(foregroundGeneration: 1),
      );
    },
  );

  test('keeps a resume failure visible while an in-place retry runs', () async {
    final repository = _ControlledLifecycleRepository();
    final firstResume = repository.enqueue('resume');
    final retryResume = repository.enqueue('resume');
    final haptics = RecordingHapticFeedbackService();
    final container = _container(repository, haptics: haptics);
    addTearDown(container.dispose);
    final notifier = container.read(walletLifecycleViewModelProvider.notifier);
    const failure = AppFailure(
      code: 'wallet_resume_failed',
      kind: AppFailureKind.unavailable,
      userMessage: 'The wallet could not be reopened.',
      retryable: true,
    );

    final automatic = notifier.handle(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    firstResume.complete(const AppResult.failure(failure));
    expect(await automatic, isFalse);
    expect(haptics.intents, isEmpty);
    expect(
      container.read(walletLifecycleViewModelProvider).showsFailure,
      isTrue,
    );

    final retry = notifier.retry();
    final retrying = container.read(walletLifecycleViewModelProvider);
    expect(retrying.failure, failure);
    expect(retrying.transitioning, isTrue);
    expect(retrying.showsFailure, isTrue);
    await Future<void>.delayed(Duration.zero);
    retryResume.complete(const AppResult.success(null));
    expect(await retry, isTrue);

    expect(
      container.read(walletLifecycleViewModelProvider),
      const WalletLifecycleState(foregroundGeneration: 1),
    );
    expect(haptics.intents, [HapticIntent.success]);
  });

  test('fails closed for thrown lifecycle state faults', () async {
    final repository = _ControlledLifecycleRepository();
    final resume = repository.enqueue('resume');
    final container = _container(repository);
    addTearDown(container.dispose);
    final notifier = container.read(walletLifecycleViewModelProvider.notifier);

    final future = notifier.handle(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    resume.completeError(StateError('private native detail'));
    expect(await future, isFalse);
    final failed = container.read(walletLifecycleViewModelProvider);
    expect(failed.failure?.userMessage, isNot(contains('private')));
    expect(failed.failure?.code, 'internal_state_violation');
    expect(failed.failure?.kind, AppFailureKind.unknown);
    expect(failed.failure?.retryable, isFalse);
  });

  test('rejects retry after a terminal foreground failure', () async {
    final repository = _ControlledLifecycleRepository();
    final resume = repository.enqueue('resume');
    final container = _container(repository);
    addTearDown(container.dispose);
    final notifier = container.read(walletLifecycleViewModelProvider.notifier);
    const failure = AppFailure(
      code: 'wallet_storage_unavailable',
      kind: AppFailureKind.storage,
      userMessage: 'Wallet storage is unavailable.',
      retryable: false,
    );

    final automatic = notifier.handle(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    resume.complete(const AppResult.failure(failure));
    expect(await automatic, isFalse);
    expect(await notifier.retry(), isFalse);
    expect(repository.calls, ['resume']);
    expect(container.read(walletLifecycleViewModelProvider).failure, failure);
  });

  testWidgets('gate excludes content until resume and retains retry surface', (
    tester,
  ) async {
    var retries = 0;
    const failure = AppFailure(
      code: 'resume_failed',
      kind: AppFailureKind.unavailable,
      userMessage: 'Try reopening the wallet.',
      retryable: true,
    );

    Future<void> pump(WalletLifecycleState state) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AsterFeedbackScope(
            haptics: const NoopHapticFeedbackService(),
            toasts: RecordingToastPresentationService(),
            child: WalletLifecycleGate(
              state: state,
              onRetry: () => retries += 1,
              child: Scaffold(
                body: Semantics(
                  label: 'Sensitive wallet balance',
                  child: const Text('1 BTC'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pump(const WalletLifecycleState(obscured: true, transitioning: true));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Opening wallet'), findsOneWidget);
    expect(find.text('1 BTC'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Sensitive wallet balance')),
      findsNothing,
    );

    await pump(
      const WalletLifecycleState(transitioning: true, failure: failure),
    );
    expect(find.text('Wallet could not be reopened'), findsOneWidget);
    expect(find.text('1 BTC'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Sensitive wallet balance')),
      findsNothing,
    );
    expect(
      tester.widget<CustomButton>(find.byType(CustomButton)).loading,
      isTrue,
    );

    await pump(const WalletLifecycleState(failure: failure));
    await tester.tap(find.text('Retry'));
    expect(retries, 1);

    await pump(const WalletLifecycleState(foregroundGeneration: 1));
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('1 BTC'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Sensitive wallet balance')),
      findsOneWidget,
    );
  });
}

final class _RetryingWalletAccess extends WalletViewModel {
  final reloadComplete = Completer<void>();
  var attempts = 0;

  @override
  Future<WalletState> build() async => throw TimeoutException('temporary');

  @override
  Future<void> reload() async {
    attempts += 1;
    state = const AsyncLoading();
    await reloadComplete.future;
    state = AsyncError(
      const AppFailureException(
        AppFailure(
          code: 'wallet_storage_invalid',
          kind: AppFailureKind.storage,
          userMessage: 'Local wallet data could not be verified.',
          retryable: false,
          requiresReconciliation: true,
        ),
      ),
      StackTrace.current,
    );
  }
}

ProviderContainer _container(
  WalletLifecycleRepository repository, {
  HapticFeedbackService haptics = const NoopHapticFeedbackService(),
}) {
  return ProviderContainer(
    overrides: [
      walletLifecycleOperationsProvider.overrideWith((ref) async => repository),
      hapticFeedbackServiceProvider.overrideWithValue(haptics),
    ],
  );
}

final class _ControlledLifecycleRepository
    implements WalletLifecycleRepository {
  final calls = <String>[];
  final _pending = <String, Queue<Completer<AppResult<void>>>>{};

  Completer<AppResult<void>> enqueue(String operation) {
    final completer = Completer<AppResult<void>>();
    (_pending[operation] ??= Queue()).add(completer);
    return completer;
  }

  @override
  Future<AppResult<void>> dispose() => _run('dispose');

  @override
  Future<AppResult<void>> resume() => _run('resume');

  @override
  Future<AppResult<void>> suspend() => _run('suspend');

  Future<AppResult<void>> _run(String operation) {
    calls.add(operation);
    final queue = _pending[operation];
    if (queue == null || queue.isEmpty) {
      throw StateError('No controlled $operation result was registered.');
    }
    return queue.removeFirst().future;
  }
}

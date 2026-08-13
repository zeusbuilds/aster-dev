import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/transaction/presentation/models/models.dart';
import 'package:aster/features/transaction/presentation/view_model/view_models.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/presentation_fakes.dart';

void main() {
  const services = WalletServiceConfiguration(
    environment: BlockchainEnvironment.signet,
    sdkNetwork: 'utexo',
    explorerBaseUrl: 'https://mempool.space/signet',
  );
  final transactionId = 'a' * 64;
  final provider = transactionDetailsActionsViewModelProvider(
    'activity-${'b' * 64}',
    transactionId,
  );

  test('serializes copy and explorer operations with result haptics', () async {
    final clipboard = _ControlledClipboardService();
    final externalUris = _ControlledExternalUriService();
    final haptics = RecordingHapticFeedbackService();
    final container = ProviderContainer(
      overrides: [
        walletServiceConfigurationProvider.overrideWithValue(services),
        clipboardServiceProvider.overrideWithValue(clipboard),
        externalUriServiceProvider.overrideWithValue(externalUris),
        hapticFeedbackServiceProvider.overrideWithValue(haptics),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    expect(
      container.read(provider).explorerUri.toString(),
      'https://mempool.space/signet/tx/$transactionId',
    );
    final notifier = container.read(provider.notifier);

    final copyGate = Completer<AppResult<void>>();
    clipboard.next = copyGate.future;
    final copy = notifier.copyField(
      TransactionDetailField.transactionId,
      transactionId,
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(provider).copyingField,
      TransactionDetailField.transactionId,
    );
    expect(
      await notifier.copyField(
        TransactionDetailField.paymentHash,
        'payment-hash',
      ),
      isNull,
    );
    copyGate.complete(const AppResult.success(null));
    expect(await copy, isA<AppSuccess<void>>());
    expect(container.read(provider).copyingField, isNull);

    final explorerGate = Completer<AppResult<void>>();
    externalUris.next = explorerGate.future;
    final open = notifier.openExplorer();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).openingExplorer, isTrue);
    expect(await notifier.openExplorer(), isNull);
    explorerGate.complete(
      const AppResult.failure(
        AppFailure(
          code: 'external_uri_unavailable',
          kind: AppFailureKind.unavailable,
          userMessage: 'The explorer is unavailable.',
          retryable: false,
        ),
      ),
    );
    expect(await open, isA<AppFailureResult<void>>());
    expect(container.read(provider).openingExplorer, isFalse);
    expect(externalUris.opened, [
      Uri.parse('https://mempool.space/signet/tx/$transactionId'),
    ]);
    expect(haptics.intents, [HapticIntent.lightImpact, HapticIntent.error]);
  });

  test(
    'maps thrown platform faults and always clears operation state',
    () async {
      final haptics = RecordingHapticFeedbackService();
      final container = ProviderContainer(
        overrides: [
          walletServiceConfigurationProvider.overrideWithValue(services),
          clipboardServiceProvider.overrideWithValue(
            const _ThrowingClipboardService(),
          ),
          hapticFeedbackServiceProvider.overrideWithValue(haptics),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final notifier = container.read(provider.notifier);

      final result = await notifier.copyField(
        TransactionDetailField.invoice,
        'private-invoice',
      );

      final failure = (result as AppFailureResult<void>).failure;
      expect(failure.code, 'internal_state_violation');
      expect(failure.userMessage, isNot(contains('private-invoice')));
      expect(container.read(provider).copyingField, isNull);
      expect(haptics.intents, [HapticIntent.error]);
    },
  );

  test(
    'stale copy and explorer completions cannot clear rebuilt work',
    () async {
      final clipboard = _ControlledClipboardService();
      final externalUris = _ControlledExternalUriService();
      final haptics = RecordingHapticFeedbackService();
      var configuration = services;
      final container = ProviderContainer(
        overrides: [
          walletServiceConfigurationProvider.overrideWith(
            (ref) => configuration,
          ),
          clipboardServiceProvider.overrideWithValue(clipboard),
          externalUriServiceProvider.overrideWithValue(externalUris),
          hapticFeedbackServiceProvider.overrideWithValue(haptics),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final notifier = container.read(provider.notifier);

      final oldCopyGate = Completer<AppResult<void>>();
      clipboard.next = oldCopyGate.future;
      final oldCopy = notifier.copyField(
        TransactionDetailField.transactionId,
        transactionId,
      );
      await Future<void>.delayed(Duration.zero);
      configuration = const WalletServiceConfiguration(
        environment: BlockchainEnvironment.mainnet,
        sdkNetwork: 'mainnet',
        explorerBaseUrl: 'https://mempool.space',
      );
      container.invalidate(walletServiceConfigurationProvider);
      await _waitFor(
        () =>
            container.read(provider).explorerUri.toString() ==
            'https://mempool.space/tx/$transactionId',
      );
      final newCopyGate = Completer<AppResult<void>>();
      clipboard.next = newCopyGate.future;
      final newCopy = container
          .read(provider.notifier)
          .copyField(TransactionDetailField.paymentHash, 'payment-hash');

      oldCopyGate.complete(const AppResult.success(null));
      expect(await oldCopy, isNull);
      expect(
        container.read(provider).copyingField,
        TransactionDetailField.paymentHash,
      );
      expect(haptics.intents, isEmpty);
      newCopyGate.complete(const AppResult.success(null));
      expect(await newCopy, isA<AppSuccess<void>>());

      final oldExplorerGate = Completer<AppResult<void>>();
      externalUris.next = oldExplorerGate.future;
      final oldExplorer = container.read(provider.notifier).openExplorer();
      await Future<void>.delayed(Duration.zero);
      configuration = services;
      container.invalidate(walletServiceConfigurationProvider);
      await _waitFor(
        () =>
            container.read(provider).explorerUri.toString() ==
            'https://mempool.space/signet/tx/$transactionId',
      );
      final newExplorerGate = Completer<AppResult<void>>();
      externalUris.next = newExplorerGate.future;
      final newExplorer = container.read(provider.notifier).openExplorer();

      oldExplorerGate.complete(const AppResult.success(null));
      expect(await oldExplorer, isNull);
      expect(container.read(provider).openingExplorer, isTrue);
      expect(haptics.intents, [HapticIntent.lightImpact]);
      newExplorerGate.complete(const AppResult.success(null));
      expect(await newExplorer, isA<AppSuccess<void>>());
      expect(haptics.intents, [
        HapticIntent.lightImpact,
        HapticIntent.lightImpact,
      ]);
    },
  );

  test('omits explorer behavior when deployment has no explorer', () async {
    final container = ProviderContainer(
      overrides: [
        walletServiceConfigurationProvider.overrideWithValue(
          const WalletServiceConfiguration(
            environment: BlockchainEnvironment.regtest,
            sdkNetwork: 'regtest',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final unavailable = transactionDetailsActionsViewModelProvider(
      'activity-${'c' * 64}',
      transactionId,
    );
    final subscription = container.listen(unavailable, (_, _) {});
    addTearDown(subscription.close);

    expect(container.read(unavailable).explorerUri, isNull);
    expect(await container.read(unavailable.notifier).openExplorer(), isNull);
  });
}

final class _ControlledClipboardService implements ClipboardService {
  Future<AppResult<void>> next = Future.value(const AppResult.success(null));

  @override
  Future<AppResult<String?>> readText() async => const AppResult.success(null);

  @override
  Future<AppResult<void>> writeText(String value) => next;
}

final class _ControlledExternalUriService implements ExternalUriService {
  Future<AppResult<void>> next = Future.value(const AppResult.success(null));
  final opened = <Uri>[];

  @override
  Future<AppResult<void>> open(Uri uri) {
    opened.add(uri);
    return next;
  }
}

final class _ThrowingClipboardService implements ClipboardService {
  const _ThrowingClipboardService();

  @override
  Future<AppResult<String?>> readText() async => const AppResult.success(null);

  @override
  Future<AppResult<void>> writeText(String value) {
    throw StateError('private-invoice native detail');
  }
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for transaction action state.');
}

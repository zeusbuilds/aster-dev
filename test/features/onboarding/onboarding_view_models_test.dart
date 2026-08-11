import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/onboarding/domain/models/models.dart';
import 'package:aster/features/onboarding/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_viewmodel.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/onboarding_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'import normalizes words and adopts only a committed registry',
    () async {
      final harness = await OnboardingTestHarness.create();
      addTearDown(harness.dispose);
      final subscription = harness.container.listen(
        importWalletViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await harness.container.read(walletViewModelProvider.future);
      await harness.container.read(importWalletViewModelProvider.future);

      final notifier = harness.container.read(
        importWalletViewModelProvider.notifier,
      );
      notifier.updateWord(0, 'ABANDON');
      expect(
        harness.container
            .read(importWalletViewModelProvider)
            .value!
            .words
            .first,
        'abandon',
      );
      notifier.updateWord(1, 'notaword');
      expect(
        harness.container
            .read(importWalletViewModelProvider)
            .value!
            .wordStatuses[1],
        MnemonicWordStatus.invalid,
      );

      for (var index = 0; index < validTestMnemonicWords.length; index += 1) {
        notifier.updateWord(index, validTestMnemonicWords[index]);
      }
      await _waitFor(
        () =>
            harness.container
                .read(importWalletViewModelProvider)
                .value
                ?.checksumStatus ==
            MnemonicChecksumStatus.valid,
      );

      expect(await notifier.submit(), isTrue);
      final importState = harness.container
          .read(importWalletViewModelProvider)
          .value!;
      expect(importState.words, everyElement(isEmpty));
      final walletState = harness.container
          .read(walletViewModelProvider)
          .value!;
      expect(walletState.activeWallet?.name, 'Restored Wallet');
      expect(harness.engine.initializedMnemonic, validTestMnemonic);
      expect(harness.haptics.intents, contains(HapticIntent.success));
    },
  );

  test('import fails closed on an SDK-invalid checksum', () async {
    final harness = await OnboardingTestHarness.create(
      validationError: const AppFailureException(
        AppFailure(
          code: 'native_phrase_invalid',
          kind: AppFailureKind.validation,
          userMessage: 'Not rendered.',
          retryable: false,
        ),
      ),
    );
    addTearDown(harness.dispose);
    final subscription = harness.container.listen(
      importWalletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await harness.container.read(importWalletViewModelProvider.future);
    final notifier = harness.container.read(
      importWalletViewModelProvider.notifier,
    );

    for (var index = 0; index < validTestMnemonicWords.length; index += 1) {
      notifier.updateWord(index, validTestMnemonicWords[index]);
    }
    await _waitFor(
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.checksumStatus ==
          MnemonicChecksumStatus.invalid,
    );

    final state = harness.container.read(importWalletViewModelProvider).value!;
    expect(state.canSubmit, isFalse);
    expect(await notifier.submit(), isFalse);
    expect(harness.engine.calls, isEmpty);
  });

  test(
    'import suppresses duplicate provisioning while native work runs',
    () async {
      final harness = await OnboardingTestHarness.create();
      addTearDown(harness.dispose);
      final subscription = harness.container.listen(
        importWalletViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await harness.container.read(walletViewModelProvider.future);
      await harness.container.read(importWalletViewModelProvider.future);
      final notifier = harness.container.read(
        importWalletViewModelProvider.notifier,
      );
      for (var index = 0; index < validTestMnemonicWords.length; index += 1) {
        notifier.updateWord(index, validTestMnemonicWords[index]);
      }
      await _waitFor(
        () =>
            harness.container
                .read(importWalletViewModelProvider)
                .value
                ?.canSubmit ==
            true,
      );
      final gate = Completer<void>();
      harness.engine.initializeGate = gate;

      final first = notifier.submit();
      expect(await notifier.submit(), isFalse);
      await _waitFor(() => harness.engine.calls.contains('initialize'));
      expect(
        harness.engine.calls.where((call) => call == 'initialize'),
        hasLength(1),
      );

      gate.complete();
      expect(await first, isTrue);
    },
  );

  test('import ignores a stale checksum result after input changes', () async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(harness.dispose);
    final subscription = harness.container.listen(
      importWalletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await harness.container.read(importWalletViewModelProvider.future);
    final notifier = harness.container.read(
      importWalletViewModelProvider.notifier,
    );
    final validationGate = Completer<void>();
    harness.keyGenerator.validationGate = validationGate;

    notifier.updateWords(0, validTestMnemonicWords);
    await _waitFor(() => harness.keyGenerator.validatedMnemonics.isNotEmpty);
    notifier.updateWord(11, 'notaword');
    validationGate.complete();
    await _waitFor(() => harness.keyGenerator.validationCompletionCount == 1);
    await Future<void>.delayed(Duration.zero);

    final state = harness.container.read(importWalletViewModelProvider).value!;
    expect(state.wordStatuses.last, MnemonicWordStatus.invalid);
    expect(state.checksumStatus, MnemonicChecksumStatus.incomplete);
    expect(state.canSubmit, isFalse);
  });

  test(
    'create copies, provisions, clears, and adopts the exact wallet',
    () async {
      final harness = await OnboardingTestHarness.create();
      addTearDown(harness.dispose);
      final subscription = harness.container.listen(
        createWalletViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await harness.container.read(walletViewModelProvider.future);
      final generated = await harness.container.read(
        createWalletViewModelProvider.future,
      );
      expect(generated.words, validTestMnemonicWords);

      final notifier = harness.container.read(
        createWalletViewModelProvider.notifier,
      );
      expect(await notifier.copyMnemonic(), isA<AppSuccess<void>>());
      expect(harness.clipboardText, validTestMnemonic);
      expect(await notifier.submit(), isTrue);
      await _waitFor(() => harness.clipboardText.isEmpty);

      final createState = harness.container
          .read(createWalletViewModelProvider)
          .value!;
      expect(createState.completed, isTrue);
      expect(createState.words, isEmpty);
      expect(
        harness.container
            .read(walletViewModelProvider)
            .value!
            .activeWallet
            ?.name,
        'Primary Wallet',
      );
      expect(
        harness.haptics.intents,
        containsAll([HapticIntent.lightImpact, HapticIntent.success]),
      );
      for (final key in harness.preferences.getKeys()) {
        expect(
          harness.preferences.get(key).toString(),
          isNot(contains('abandon')),
        );
      }
    },
  );

  test(
    'create serializes copy and disables provisioning until it settles',
    () async {
      final clipboardGate = Completer<void>();
      final harness = await OnboardingTestHarness.create(
        clipboardWriteGate: clipboardGate,
      );
      addTearDown(harness.dispose);
      final subscription = harness.container.listen(
        createWalletViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await harness.container.read(walletViewModelProvider.future);
      await harness.container.read(createWalletViewModelProvider.future);
      final notifier = harness.container.read(
        createWalletViewModelProvider.notifier,
      );

      final copy = notifier.copyMnemonic();
      expect(
        harness.container.read(createWalletViewModelProvider).value?.copying,
        isTrue,
      );
      expect(await notifier.submit(), isFalse);
      expect(await notifier.copyMnemonic(), isA<AppFailureResult<void>>());

      clipboardGate.complete();
      expect(await copy, isA<AppSuccess<void>>());
      expect(
        harness.container.read(createWalletViewModelProvider).value?.copying,
        isFalse,
      );
    },
  );

  test('create retains its phrase when native provisioning fails', () async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(harness.dispose);
    final subscription = harness.container.listen(
      createWalletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await harness.container.read(walletViewModelProvider.future);
    await harness.container.read(createWalletViewModelProvider.future);
    harness.engine.initializeError = const AppFailureException(
      AppFailure(
        code: 'test_wallet_unavailable',
        kind: AppFailureKind.unavailable,
        userMessage: 'Wallet setup is temporarily unavailable.',
        retryable: true,
      ),
    );

    final created = await harness.container
        .read(createWalletViewModelProvider.notifier)
        .submit();

    expect(created, isFalse);
    final state = harness.container.read(createWalletViewModelProvider).value!;
    expect(state.words, validTestMnemonicWords);
    expect(state.failure?.code, 'test_wallet_unavailable');
    expect(state.canSubmit, isTrue);
    expect(
      harness.container.read(walletViewModelProvider).value?.activeWallet,
      isNull,
    );
    expect(harness.haptics.intents, contains(HapticIntent.error));
    expect(harness.engine.calls, containsAllInOrder(['initialize', 'destroy']));
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for asynchronous state.');
}

import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/onboarding/data/repository/repository.dart';
import 'package:aster/features/onboarding/domain/models/models.dart';
import 'package:aster/features/onboarding/presentation/models/models.dart';
import 'package:aster/features/onboarding/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/onboarding_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('import state requires known words as well as a valid checksum', () {
    final malformed = ImportWalletState(
      checksumStatus: MnemonicChecksumStatus.valid,
    );

    expect(malformed.allWordsKnown, isFalse);
    expect(malformed.canSubmit, isFalse);

    final mismatched = ImportWalletState(
      words: List.filled(ImportWalletState.wordCount, ''),
      wordStatuses: List.filled(
        ImportWalletState.wordCount,
        MnemonicWordStatus.valid,
      ),
      checksumStatus: MnemonicChecksumStatus.valid,
    );
    expect(mismatched.allWordsKnown, isFalse);
    expect(mismatched.canSubmit, isFalse);
  });

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
      notifier.updateWord(0, 'ABAN-DON123');
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
      notifier.updateWord(2, 'NOTA-WORD-THAT-IS-TOO-LONG');
      expect(
        harness.container.read(importWalletViewModelProvider).value!.words[2],
        'notaword',
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
      expect(
        harness.container
            .read(importWalletViewModelProvider)
            .requireValue
            .canContinue,
        isTrue,
      );
      expect(
        harness.container
            .read(importWalletViewModelProvider)
            .requireValue
            .canSubmit,
        isFalse,
      );
      notifier.updateWalletName('Imported savings');

      expect(await notifier.submit(), isTrue);
      final importState = harness.container
          .read(importWalletViewModelProvider)
          .value!;
      expect(importState.words, everyElement(isEmpty));
      expect(importState.completed, isTrue);
      expect(importState.canContinue, isFalse);
      final walletState = harness.container
          .read(walletViewModelProvider)
          .value!;
      expect(walletState.activeWallet?.name, 'Imported savings');
      expect(harness.engine.provisionedMnemonic, validTestMnemonic);
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
      notifier.updateWalletName('Imported wallet');
      await _waitFor(
        () =>
            harness.container
                .read(importWalletViewModelProvider)
                .value
                ?.canSubmit ==
            true,
      );
      final gate = Completer<void>();
      harness.engine.provisionGate = gate;

      final first = notifier.submit();
      expect(await notifier.submit(), isFalse);
      await _waitFor(() => harness.engine.calls.contains('provision'));
      expect(
        harness.engine.calls.where((call) => call == 'provision'),
        hasLength(1),
      );

      gate.complete();
      expect(await first, isTrue);
    },
  );

  test(
    'import retains a provisioning failure as a retryable submit state',
    () async {
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
      notifier.updateWords(0, validTestMnemonicWords);
      notifier.updateWalletName('Imported wallet');
      await _waitFor(
        () =>
            harness.container
                .read(importWalletViewModelProvider)
                .value
                ?.canSubmit ==
            true,
      );
      harness.engine.provisionError = const AppFailureException(
        AppFailure(
          code: 'wallet_setup_unavailable',
          kind: AppFailureKind.unavailable,
          userMessage: 'Wallet setup is temporarily unavailable.',
          retryable: true,
        ),
      );

      expect(await notifier.submit(), isFalse);
      final failed = harness.container
          .read(importWalletViewModelProvider)
          .requireValue;
      expect(failed.checksumStatus, MnemonicChecksumStatus.valid);
      expect(failed.failure?.code, 'wallet_setup_unavailable');
      expect(failed.canSubmit, isTrue);
      final validationCount = harness.keyGenerator.validatedMnemonics.length;
      await notifier.retryChecksum();
      expect(
        harness.keyGenerator.validatedMnemonics,
        hasLength(validationCount),
      );
    },
  );

  test('import quarantines an outcome-unknown provisioning result', () async {
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
    notifier.updateWords(0, validTestMnemonicWords);
    notifier.updateWalletName('Imported wallet');
    await _waitFor(
      () =>
          harness.container
              .read(importWalletViewModelProvider)
              .value
              ?.canSubmit ==
          true,
    );
    harness.engine.provisionError = const AppFailureException(
      AppFailure(
        code: 'wallet_setup_outcome_unknown',
        kind: AppFailureKind.timeout,
        userMessage: 'Restart before continuing wallet setup.',
        retryable: false,
        outcomeUnknown: true,
      ),
    );

    expect(await notifier.submit(), isFalse);
    final failed = harness.container
        .read(importWalletViewModelProvider)
        .requireValue;
    expect(failed.requiresReconciliation, isTrue);
    expect(failed.canSubmit, isFalse);
    expect(failed.words, validTestMnemonicWords);
    final callsAfterFailure = List<String>.of(harness.engine.calls);

    notifier.updateWord(11, 'ability');
    await notifier.retryChecksum();
    expect(await notifier.submit(), isFalse);

    final quarantined = harness.container
        .read(importWalletViewModelProvider)
        .requireValue;
    expect(quarantined, failed);
    expect(harness.engine.calls, callsAfterFailure);
    expect(
      harness.engine.calls.where((call) => call == 'provision'),
      hasLength(1),
    );
  });

  test(
    'import freezes a known retained-resource provisioning result',
    () async {
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
      notifier.updateWords(0, validTestMnemonicWords);
      notifier.updateWalletName('Imported wallet');
      await _waitFor(
        () =>
            harness.container
                .read(importWalletViewModelProvider)
                .value
                ?.canSubmit ==
            true,
      );
      harness.engine.provisionError = const AppFailureException(
        AppFailure(
          code: 'wallet_setup_reconciliation_required',
          kind: AppFailureKind.storage,
          userMessage: 'Restart before continuing wallet setup.',
          retryable: false,
          requiresReconciliation: true,
        ),
      );

      expect(await notifier.submit(), isFalse);
      final failed = harness.container
          .read(importWalletViewModelProvider)
          .requireValue;
      expect(failed.failure?.requiresReconciliation, isTrue);
      expect(failed.failure?.outcomeUnknown, isFalse);
      expect(failed.canSubmit, isFalse);
      final callsAfterFailure = List<String>.of(harness.engine.calls);

      notifier.updateWords(0, List<String>.filled(12, 'ability'));
      await notifier.retryChecksum();
      expect(await notifier.submit(), isFalse);

      expect(
        harness.container.read(importWalletViewModelProvider).requireValue,
        failed,
      );
      expect(harness.engine.calls, callsAfterFailure);
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
    'import coalesces complete phrase edits to the latest pending checksum',
    () async {
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
      await _waitFor(() => harness.keyGenerator.validatedMnemonics.length == 1);
      notifier.updateWord(11, 'ability');
      notifier.updateWord(11, 'able');
      await Future<void>.delayed(Duration.zero);

      expect(harness.keyGenerator.validatedMnemonics, [validTestMnemonic]);
      expect(
        harness.container
            .read(importWalletViewModelProvider)
            .requireValue
            .checksumStatus,
        MnemonicChecksumStatus.checking,
      );

      validationGate.complete();
      await _waitFor(() => harness.keyGenerator.validationCompletionCount == 2);

      expect(harness.keyGenerator.validatedMnemonics, [
        validTestMnemonic,
        '${validTestMnemonicWords.take(11).join(' ')} able',
      ]);
      expect(
        harness.container
            .read(importWalletViewModelProvider)
            .requireValue
            .checksumStatus,
        MnemonicChecksumStatus.valid,
      );
    },
  );

  test(
    'import drops pending checksum work when the phrase becomes incomplete',
    () async {
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
      await _waitFor(() => harness.keyGenerator.validatedMnemonics.length == 1);
      notifier.updateWord(11, 'ability');
      notifier.updateWord(11, 'notaword');

      validationGate.complete();
      await _waitFor(() => harness.keyGenerator.validationCompletionCount == 1);
      await Future<void>.delayed(Duration.zero);

      expect(harness.keyGenerator.validatedMnemonics, [validTestMnemonic]);
      final state = harness.container
          .read(importWalletViewModelProvider)
          .requireValue;
      expect(state.wordStatuses.last, MnemonicWordStatus.invalid);
      expect(state.checksumStatus, MnemonicChecksumStatus.incomplete);
      expect(state.canSubmit, isFalse);
    },
  );

  test(
    'import retries a transient checksum failure exactly on demand',
    () async {
      final harness = await OnboardingTestHarness.create(
        validationError: const AppFailureException(
          AppFailure(
            code: 'checksum_service_unavailable',
            kind: AppFailureKind.unavailable,
            userMessage: 'Phrase checking is temporarily unavailable.',
            retryable: true,
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

      notifier.updateWords(0, validTestMnemonicWords);
      await _waitFor(
        () =>
            harness.container
                .read(importWalletViewModelProvider)
                .value
                ?.failure
                ?.code ==
            'checksum_service_unavailable',
      );
      expect(harness.keyGenerator.validatedMnemonics, hasLength(1));

      harness.keyGenerator.validationError = null;
      final retry = notifier.retryChecksum();
      await notifier.retryChecksum();
      await retry;
      final recovered = harness.container
          .read(importWalletViewModelProvider)
          .requireValue;
      expect(recovered.checksumStatus, MnemonicChecksumStatus.valid);
      expect(recovered.failure, isNull);
      expect(recovered.canContinue, isTrue);
      expect(recovered.canSubmit, isFalse);
      notifier.updateWalletName('Imported wallet');
      expect(
        harness.container
            .read(importWalletViewModelProvider)
            .requireValue
            .canSubmit,
        isTrue,
      );
      notifier.discardWalletNameDraft();
      final discarded = harness.container
          .read(importWalletViewModelProvider)
          .requireValue;
      expect(discarded.walletName, isEmpty);
      expect(discarded.canSubmit, isFalse);
      expect(harness.keyGenerator.validatedMnemonics, hasLength(2));
    },
  );

  test(
    'create requires fixed backup confirmation and a valid wallet name',
    () async {
      final harness = await OnboardingTestHarness.create();
      addTearDown(harness.dispose);
      final subscription = harness.container.listen(
        createWalletViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final generated = await harness.container.read(
        createWalletViewModelProvider.future,
      );
      final notifier = harness.container.read(
        createWalletViewModelProvider.notifier,
      );

      expect(
        generated.questions.map((question) => question.wordNumber),
        orderedEquals(CreateWalletState.quizWordNumbers),
      );
      final wordListResult = await harness.container
          .read(bip39WordListRepositoryProvider)
          .load();
      final wordList = switch (wordListResult) {
        AppSuccess<Bip39WordList>(:final value) => value,
        AppFailureResult<Bip39WordList>() => fail(
          'The integrity-checked BIP39 list must load in the test harness.',
        ),
      };
      final phraseWords = generated.words.toSet();
      for (final question in generated.questions) {
        expect(question.options, hasLength(RecoveryPhraseQuestion.optionCount));
        expect(
          question.options.toSet(),
          hasLength(RecoveryPhraseQuestion.optionCount),
        );
        expect(question.options, contains(question.expectedWord));
        expect(question.options.every(wordList.contains), isTrue);
        expect(
          question.options.where(phraseWords.contains),
          orderedEquals([question.expectedWord]),
        );
      }
      expect(generated.canSubmit, isFalse);
      final first = generated.questions.first;
      final incorrect = first.options.firstWhere(
        (option) => option != first.expectedWord,
      );
      expect(
        notifier.selectQuizOption(
          wordNumber: first.wordNumber,
          word: incorrect,
        ),
        isFalse,
      );
      expect(
        harness.container
            .read(createWalletViewModelProvider)
            .requireValue
            .confirmedQuestionCount,
        0,
      );

      _completeCreateQuiz(notifier, generated);
      expect(
        harness.container
            .read(createWalletViewModelProvider)
            .requireValue
            .quizComplete,
        isTrue,
      );
      expect(
        harness.container
            .read(createWalletViewModelProvider)
            .requireValue
            .canSubmit,
        isFalse,
      );
      notifier.updateWalletName('   ');
      expect(
        harness.container
            .read(createWalletViewModelProvider)
            .requireValue
            .canSubmit,
        isFalse,
      );
      notifier.updateWalletName('Daily wallet');
      expect(
        harness.container
            .read(createWalletViewModelProvider)
            .requireValue
            .canSubmit,
        isTrue,
      );
      notifier.discardWalletNameDraft();
      final discarded = harness.container
          .read(createWalletViewModelProvider)
          .requireValue;
      expect(discarded.walletName, isEmpty);
      expect(discarded.canSubmit, isFalse);
    },
  );

  test(
    'create keeps phrase offline, provisions, and adopts the exact wallet',
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
      _completeCreateQuiz(notifier, generated);
      notifier.updateWalletName('Daily wallet');
      expect(await notifier.copyMnemonic(), isA<AppFailureResult<void>>());
      expect(harness.clipboardText, isEmpty);
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
        'Daily wallet',
      );
      expect(harness.haptics.intents, contains(HapticIntent.success));
      for (final key in harness.preferences.getKeys()) {
        expect(
          harness.preferences.get(key).toString(),
          isNot(contains('abandon')),
        );
      }
    },
  );

  test(
    'direct recovery-copy calls stay disabled without blocking provisioning',
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
      final notifier = harness.container.read(
        createWalletViewModelProvider.notifier,
      );
      _completeCreateQuiz(notifier, generated);
      notifier.updateWalletName('Daily wallet');
      final result = await notifier.copyMnemonic();
      expect(result, isA<AppFailureResult<void>>());
      expect(
        (result as AppFailureResult<void>).failure.code,
        'sensitive_clipboard_disabled',
      );
      expect(harness.clipboardText, isEmpty);
      expect(
        harness.container.read(createWalletViewModelProvider).value?.copying,
        isFalse,
      );
      expect(await notifier.submit(), isTrue);
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
    final generated = await harness.container.read(
      createWalletViewModelProvider.future,
    );
    final notifier = harness.container.read(
      createWalletViewModelProvider.notifier,
    );
    _completeCreateQuiz(notifier, generated);
    notifier.updateWalletName('Daily wallet');
    harness.engine.provisionError = const AppFailureException(
      AppFailure(
        code: 'test_wallet_unavailable',
        kind: AppFailureKind.unavailable,
        userMessage: 'Wallet setup is temporarily unavailable.',
        retryable: true,
      ),
    );

    final created = await notifier.submit();

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
    expect(harness.engine.calls, containsAllInOrder(['provision', 'destroy']));
  });

  test(
    'create blocks outcome-unknown replay and keeps phrase offline',
    () async {
      final harness = await OnboardingTestHarness.create();
      addTearDown(harness.dispose);
      final subscription = harness.container.listen(
        createWalletViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final generated = await harness.container.read(
        createWalletViewModelProvider.future,
      );
      final notifier = harness.container.read(
        createWalletViewModelProvider.notifier,
      );
      _completeCreateQuiz(notifier, generated);
      notifier.updateWalletName('Daily wallet');
      harness.engine.provisionError = const AppFailureException(
        AppFailure(
          code: 'wallet_setup_outcome_unknown',
          kind: AppFailureKind.timeout,
          userMessage: 'Restart before continuing wallet setup.',
          retryable: false,
          outcomeUnknown: true,
        ),
      );

      expect(await notifier.submit(), isFalse);
      final failed = harness.container
          .read(createWalletViewModelProvider)
          .requireValue;
      expect(failed.canSubmit, isFalse);
      expect(failed.canContinue, isTrue);
      expect(failed.words, validTestMnemonicWords);
      final callsAfterFailure = List<String>.of(harness.engine.calls);

      expect(await notifier.copyMnemonic(), isA<AppFailureResult<void>>());
      expect(await notifier.submit(), isFalse);

      expect(harness.clipboardText, isEmpty);
      expect(harness.engine.calls, callsAfterFailure);
      expect(
        harness.engine.calls.where((call) => call == 'provision'),
        hasLength(1),
      );
    },
  );

  test(
    'create blocks retained-resource replay and keeps phrase offline',
    () async {
      final harness = await OnboardingTestHarness.create();
      addTearDown(harness.dispose);
      final subscription = harness.container.listen(
        createWalletViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final generated = await harness.container.read(
        createWalletViewModelProvider.future,
      );
      final notifier = harness.container.read(
        createWalletViewModelProvider.notifier,
      );
      _completeCreateQuiz(notifier, generated);
      notifier.updateWalletName('Daily wallet');
      harness.engine.provisionError = const AppFailureException(
        AppFailure(
          code: 'wallet_setup_reconciliation_required',
          kind: AppFailureKind.storage,
          userMessage: 'Restart before continuing wallet setup.',
          retryable: false,
          requiresReconciliation: true,
        ),
      );

      expect(await notifier.submit(), isFalse);
      final failed = harness.container
          .read(createWalletViewModelProvider)
          .requireValue;
      expect(failed.failure?.requiresReconciliation, isTrue);
      expect(failed.failure?.outcomeUnknown, isFalse);
      expect(failed.canSubmit, isFalse);
      expect(failed.canContinue, isTrue);
      final callsAfterFailure = List<String>.of(harness.engine.calls);

      expect(await notifier.copyMnemonic(), isA<AppFailureResult<void>>());
      expect(await notifier.submit(), isFalse);

      expect(harness.clipboardText, isEmpty);
      expect(harness.engine.calls, callsAfterFailure);
    },
  );
}

void _completeCreateQuiz(
  CreateWalletViewModel notifier,
  CreateWalletState state,
) {
  for (final question in state.questions) {
    expect(
      notifier.selectQuizOption(
        wordNumber: question.wordNumber,
        word: question.expectedWord,
      ),
      isTrue,
    );
  }
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for asynchronous state.');
}

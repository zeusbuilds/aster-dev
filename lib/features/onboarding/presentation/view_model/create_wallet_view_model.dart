import 'dart:async';
import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../../shared/feedback/feedback.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/wallet_view_model.dart';
import '../../data/repository/repository.dart';
import '../models/models.dart';

part 'create_wallet_view_model.g.dart';

/// Cryptographically strong entropy for recovery-quiz choice construction.
@riverpod
Random recoveryQuizRandom(Ref ref) => Random.secure();

/// Owns generated phrase display, bounded clipboard access, and provisioning.
@riverpod
class CreateWalletViewModel extends _$CreateWalletViewModel {
  late SensitiveClipboardService _clipboard;

  @override
  Future<CreateWalletState> build() async {
    _clipboard = ref.watch(sensitiveClipboardServiceProvider);
    final wordListRepository = ref.watch(bip39WordListRepositoryProvider);
    final quizRandom = ref.watch(recoveryQuizRandomProvider);
    ref.onDispose(() => unawaited(_clipboard.clearSensitive()));
    final wordListResult = await wordListRepository.load();
    final wordList = switch (wordListResult) {
      AppSuccess<Bip39WordList>(:final value) => value,
      AppFailureResult<Bip39WordList>(:final failure) =>
        throw AppFailureException(failure),
    };
    final result = await _generateMnemonic();
    return switch (result) {
      AppSuccess<String>(:final value) => () {
        final words = value.split(' ');
        return CreateWalletState(
          words: words,
          questions: _buildQuestions(words, wordList, quizRandom),
        );
      }(),
      AppFailureResult<String>(:final failure) => throw AppFailureException(
        failure,
      ),
    };
  }

  /// Confirms only the current fixed-position prompt and advances on success.
  bool selectQuizOption(String word) {
    final current = state.value;
    final question = current?.currentQuestion;
    if (current == null ||
        question == null ||
        current.submitting ||
        current.requiresReconciliation ||
        !question.options.contains(word)) {
      return false;
    }
    if (!question.accepts(word)) {
      state = AsyncData(current.copyWith(rejectedQuizOption: word));
      unawaited(
        ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.error),
      );
      return false;
    }
    state = AsyncData(
      current.copyWith(
        confirmedQuestionCount: current.confirmedQuestionCount + 1,
        rejectedQuizOption: null,
      ),
    );
    unawaited(
      ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.selection),
    );
    return true;
  }

  /// Updates the user-facing name without exposing phrase material to the UI.
  void updateWalletName(String name) {
    final current = state.value;
    if (current == null ||
        current.submitting ||
        current.requiresReconciliation ||
        current.completed ||
        current.walletName == name) {
      return;
    }
    state = AsyncData(current.copyWith(walletName: name, failure: null));
  }

  /// Copies the phrase under a bounded matching-content clipboard lease.
  Future<AppResult<void>> copyMnemonic() async {
    final current = state.value;
    if (current == null || !current.canCopy) {
      return AppResult.failure(
        const AppFailure(
          code: 'clipboard_action_unavailable',
          kind: AppFailureKind.conflict,
          userMessage: 'The recovery phrase is not available to copy.',
          retryable: false,
        ),
      );
    }
    state = AsyncData(current.copyWith(copying: true));
    final result = await _clipboard.copySensitive(current.mnemonic);
    if (!ref.mounted) return result;
    state = AsyncData(current.copyWith(copying: false));
    final intent = result is AppSuccess<void>
        ? HapticIntent.lightImpact
        : HapticIntent.error;
    unawaited(ref.read(hapticFeedbackServiceProvider).trigger(intent));
    return result;
  }

  /// Provisions the displayed phrase and publishes only its committed registry.
  Future<bool> submit() async {
    final current = state.value;
    if (current == null || !current.canSubmit) return false;
    state = AsyncData(current.copyWith(submitting: true, failure: null));
    final result = await _createWallet(
      current.mnemonic,
      current.normalizedWalletName,
    );
    if (!ref.mounted) return result is AppSuccess<WalletRegistry>;
    return switch (result) {
      AppSuccess<WalletRegistry>(:final value) => _completeProvisioning(
        current,
        value,
      ),
      AppFailureResult<WalletRegistry>(:final failure) => () {
        state = AsyncData(
          current.copyWith(submitting: false, failure: failure),
        );
        unawaited(
          ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.error),
        );
        return false;
      }(),
    };
  }

  Future<bool> _completeProvisioning(
    CreateWalletState current,
    WalletRegistry registry,
  ) async {
    // The durable wallet commit must not retain the clipboard lease. A failed
    // clear remains leased and is retried by the clipboard service.
    await _clipboard.clearSensitive();
    if (!ref.mounted) return true;
    state = AsyncData(current.cleared());
    unawaited(
      ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.success),
    );
    ref.read(walletViewModelProvider.notifier).adoptCommittedRegistry(registry);
    return true;
  }

  Future<AppResult<String>> _generateMnemonic() async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return await repository.generateMnemonic();
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  Future<AppResult<WalletRegistry>> _createWallet(
    String mnemonic,
    String name,
  ) async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return await repository.createFromMnemonic(
        mnemonic: mnemonic,
        name: name,
      );
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  static List<RecoveryPhraseQuestion> _buildQuestions(
    List<String> words,
    Bip39WordList wordList,
    Random random,
  ) {
    final phraseWords = words.toSet();
    final distractorPool = <String>[
      for (var index = 0; index < wordList.length; index += 1)
        if (!phraseWords.contains(wordList.wordAt(index)))
          wordList.wordAt(index),
    ];
    if (distractorPool.length < RecoveryPhraseQuestion.optionCount - 1) {
      throw const FormatException(
        'BIP39 vocabulary cannot provide distinct quiz options.',
      );
    }
    return [
      for (
        var questionIndex = 0;
        questionIndex < CreateWalletState.quizWordNumbers.length;
        questionIndex += 1
      )
        () {
          final wordNumber = CreateWalletState.quizWordNumbers[questionIndex];
          final expectedWord = words[wordNumber - 1];
          final expectedIndex = wordList.indexOf(expectedWord);
          if (expectedIndex == null) {
            throw const FormatException(
              'Generated recovery phrase contains a non-BIP39 word.',
            );
          }
          final sample = List<String>.of(distractorPool);
          final distractorCount = RecoveryPhraseQuestion.optionCount - 1;
          for (var index = 0; index < distractorCount; index += 1) {
            final swapIndex = index + random.nextInt(sample.length - index);
            final displaced = sample[index];
            sample[index] = sample[swapIndex];
            sample[swapIndex] = displaced;
          }
          final options = <String>[
            expectedWord,
            ...sample.take(distractorCount),
          ]..shuffle(random);
          return RecoveryPhraseQuestion(
            wordNumber: wordNumber,
            expectedWord: expectedWord,
            options: options,
          );
        }(),
    ];
  }
}

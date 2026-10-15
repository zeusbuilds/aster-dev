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

/// Owns generated phrase display, offline confirmation, and provisioning.
@riverpod
class CreateWalletViewModel extends _$CreateWalletViewModel {
  @override
  Future<CreateWalletState> build() async {
    final wordListRepository = ref.watch(bip39WordListRepositoryProvider);
    final quizRandom = ref.watch(recoveryQuizRandomProvider);
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

  /// Selects one option for a fixed-position recovery prompt.
  bool selectQuizOption({required int wordNumber, required String word}) {
    final current = state.value;
    final question = current?.questions
        .where((candidate) => candidate.wordNumber == wordNumber)
        .firstOrNull;
    if (current == null ||
        question == null ||
        current.submitting ||
        current.requiresReconciliation ||
        current.isQuestionConfirmed(question) ||
        current.selectedOptionFor(wordNumber) == word ||
        !question.options.contains(word)) {
      return false;
    }
    state = AsyncData(
      current.copyWith(
        quizSelections: {...current.quizSelections, wordNumber: word},
      ),
    );
    if (!question.accepts(word)) {
      unawaited(
        ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.error),
      );
      return false;
    }
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

  /// Abandons the naming-step draft when the user navigates backward.
  void discardWalletNameDraft() {
    final current = state.value;
    if (current == null ||
        current.submitting ||
        current.completed ||
        current.requiresReconciliation ||
        (current.walletName.isEmpty && current.failure == null)) {
      return;
    }
    state = AsyncData(current.copyWith(walletName: '', failure: null));
  }

  /// Secret copying is deliberately unavailable, including direct callers.
  Future<AppResult<void>> copyMnemonic() =>
      const PlatformSensitiveClipboardService().copySensitive('');

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

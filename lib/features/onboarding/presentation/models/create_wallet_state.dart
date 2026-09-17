import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../wallet/domain/models/models.dart';

/// One fixed-position recovery-phrase confirmation prompt.
@immutable
final class RecoveryPhraseQuestion {
  RecoveryPhraseQuestion({
    required this.wordNumber,
    required this.expectedWord,
    required List<String> options,
  }) : options = List<String>.unmodifiable(options) {
    if (wordNumber < 1 ||
        wordNumber > CreateWalletState.wordCount ||
        expectedWord.isEmpty ||
        this.options.length != optionCount ||
        this.options.toSet().length != optionCount ||
        !this.options.contains(expectedWord)) {
      throw ArgumentError('Recovery-phrase question is malformed.');
    }
  }

  static const optionCount = 4;

  /// One-based position in the displayed 12-word recovery phrase.
  final int wordNumber;

  /// Expected canonical BIP39 word. It remains route-owned secret material.
  final String expectedWord;

  /// Stable choices for this prompt. They never change across rebuilds.
  final List<String> options;

  bool accepts(String word) => word == expectedWord;

  @override
  bool operator ==(Object other) =>
      other is RecoveryPhraseQuestion &&
      other.wordNumber == wordNumber &&
      other.expectedWord == expectedWord &&
      listEquals(other.options, options);

  @override
  int get hashCode =>
      Object.hash(wordNumber, expectedWord, Object.hashAll(options));
}

/// Route-scoped recovery phrase, confirmation, naming, and provisioning state.
@immutable
final class CreateWalletState {
  CreateWalletState({
    required List<String> words,
    required List<RecoveryPhraseQuestion> questions,
    this.confirmedQuestionCount = 0,
    this.rejectedQuizOption,
    this.walletName = '',
    this.copying = false,
    this.submitting = false,
    this.completed = false,
    this.failure,
  }) : words = List<String>.unmodifiable(words),
       questions = List<RecoveryPhraseQuestion>.unmodifiable(questions) {
    final validPhrase =
        this.words.length == wordCount &&
        this.words.every((word) => word.isNotEmpty);
    final validQuestions =
        this.questions.length == quizWordNumbers.length &&
        listEquals(
          this.questions.map((question) => question.wordNumber).toList(),
          quizWordNumbers,
        ) &&
        this.questions.every(
          (question) =>
              question.expectedWord == this.words[question.wordNumber - 1],
        );
    if ((!completed && (!validPhrase || !validQuestions)) ||
        (completed && (this.words.isNotEmpty || this.questions.isNotEmpty))) {
      throw ArgumentError(
        'Create state requires a valid phrase and confirmation quiz.',
      );
    }
    if (confirmedQuestionCount < 0 ||
        confirmedQuestionCount > this.questions.length) {
      throw ArgumentError.value(
        confirmedQuestionCount,
        'confirmedQuestionCount',
      );
    }
    final rejectedOptionIsValid =
        rejectedQuizOption == null ||
        (confirmedQuestionCount < this.questions.length &&
            this.questions[confirmedQuestionCount].options.contains(
              rejectedQuizOption,
            ) &&
            rejectedQuizOption !=
                this.questions[confirmedQuestionCount].expectedWord);
    if (!rejectedOptionIsValid) {
      throw ArgumentError.value(
        rejectedQuizOption,
        'rejectedQuizOption',
        'Must be an incorrect option for the current question.',
      );
    }
    if ((copying && submitting) || (completed && (copying || submitting))) {
      throw ArgumentError('Create state cannot own overlapping operations.');
    }
  }

  static const wordCount = 12;

  /// Fixed one-based positions, verifying one word in every three.
  static const quizWordNumbers = <int>[3, 6, 9, 12];

  final List<String> words;
  final List<RecoveryPhraseQuestion> questions;
  final int confirmedQuestionCount;
  final String? rejectedQuizOption;
  final String walletName;
  final bool copying;
  final bool submitting;
  final bool completed;
  final AppFailure? failure;

  /// Whether the route still owns a phrase that can be copied safely.
  bool get canCopy => !copying && !submitting && !completed;

  /// Whether retained or uncertain wallet resources require reconciliation.
  bool get requiresReconciliation => failure?.requiresReconciliation ?? false;

  bool get quizComplete => confirmedQuestionCount == questions.length;

  RecoveryPhraseQuestion? get currentQuestion =>
      quizComplete ? null : questions[confirmedQuestionCount];

  String get normalizedWalletName => walletName.trim();

  bool get walletNameValid => WalletProfile.isValidName(normalizedWalletName);

  /// Whether provisioning may start or explicitly retry a known-safe failure.
  bool get canSubmit =>
      !copying &&
      !submitting &&
      !completed &&
      quizComplete &&
      walletNameValid &&
      (failure == null || failure!.retryable);

  String get mnemonic => words.join(' ');

  CreateWalletState copyWith({
    int? confirmedQuestionCount,
    Object? rejectedQuizOption = _unchanged,
    String? walletName,
    bool? copying,
    bool? submitting,
    bool? completed,
    Object? failure = _unchanged,
  }) {
    return CreateWalletState(
      words: words,
      questions: questions,
      confirmedQuestionCount:
          confirmedQuestionCount ?? this.confirmedQuestionCount,
      rejectedQuizOption: identical(rejectedQuizOption, _unchanged)
          ? this.rejectedQuizOption
          : rejectedQuizOption as String?,
      walletName: walletName ?? this.walletName,
      copying: copying ?? this.copying,
      submitting: submitting ?? this.submitting,
      completed: completed ?? this.completed,
      failure: identical(failure, _unchanged)
          ? this.failure
          : failure as AppFailure?,
    );
  }

  /// Releases every route-owned reference after a confirmed durable commit.
  CreateWalletState cleared() =>
      CreateWalletState(words: const [], questions: const [], completed: true);

  @override
  bool operator ==(Object other) {
    return other is CreateWalletState &&
        listEquals(other.words, words) &&
        listEquals(other.questions, questions) &&
        other.confirmedQuestionCount == confirmedQuestionCount &&
        other.rejectedQuizOption == rejectedQuizOption &&
        other.walletName == walletName &&
        other.copying == copying &&
        other.submitting == submitting &&
        other.completed == completed &&
        other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(words),
    Object.hashAll(questions),
    confirmedQuestionCount,
    rejectedQuizOption,
    walletName,
    copying,
    submitting,
    completed,
    failure,
  );
}

const _unchanged = Object();

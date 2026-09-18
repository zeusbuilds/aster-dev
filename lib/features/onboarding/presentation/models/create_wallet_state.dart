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

  static const optionCount = 3;

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

/// Flow-scoped recovery phrase, confirmation, naming, and provisioning state.
@immutable
final class CreateWalletState {
  CreateWalletState({
    required List<String> words,
    required List<RecoveryPhraseQuestion> questions,
    Map<int, String> quizSelections = const {},
    this.walletName = '',
    this.copying = false,
    this.submitting = false,
    this.completed = false,
    this.failure,
  }) : words = List<String>.unmodifiable(words),
       questions = List<RecoveryPhraseQuestion>.unmodifiable(questions),
       quizSelections = Map<int, String>.unmodifiable(quizSelections) {
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
        (completed &&
            (this.words.isNotEmpty ||
                this.questions.isNotEmpty ||
                this.quizSelections.isNotEmpty))) {
      throw ArgumentError(
        'Create state requires a valid phrase and confirmation quiz.',
      );
    }
    final questionsByWordNumber = {
      for (final question in this.questions) question.wordNumber: question,
    };
    final validSelections = this.quizSelections.entries.every((entry) {
      final question = questionsByWordNumber[entry.key];
      return question != null && question.options.contains(entry.value);
    });
    if (!validSelections) {
      throw ArgumentError.value(
        this.quizSelections,
        'quizSelections',
        'Selections must identify one of the options for a quiz word.',
      );
    }
    if ((copying && submitting) || (completed && (copying || submitting))) {
      throw ArgumentError('Create state cannot own overlapping operations.');
    }
  }

  static const wordCount = 12;

  /// Fixed one-based positions distributed across the recovery phrase.
  static const quizWordNumbers = <int>[3, 7, 11];

  final List<String> words;
  final List<RecoveryPhraseQuestion> questions;

  /// Current choice for each prompt, keyed by its one-based word position.
  final Map<int, String> quizSelections;
  final String walletName;
  final bool copying;
  final bool submitting;
  final bool completed;
  final AppFailure? failure;

  /// Whether the flow still owns a phrase that can be copied safely.
  bool get canCopy => !copying && !submitting && !completed;

  /// Whether retained or uncertain wallet resources require reconciliation.
  bool get requiresReconciliation => failure?.requiresReconciliation ?? false;

  int get confirmedQuestionCount => questions
      .where(
        (question) =>
            quizSelections[question.wordNumber] == question.expectedWord,
      )
      .length;

  bool get quizComplete => confirmedQuestionCount == questions.length;

  String? selectedOptionFor(int wordNumber) => quizSelections[wordNumber];

  bool isQuestionConfirmed(RecoveryPhraseQuestion question) =>
      selectedOptionFor(question.wordNumber) == question.expectedWord;

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
    Map<int, String>? quizSelections,
    String? walletName,
    bool? copying,
    bool? submitting,
    bool? completed,
    Object? failure = _unchanged,
  }) {
    return CreateWalletState(
      words: words,
      questions: questions,
      quizSelections: quizSelections ?? this.quizSelections,
      walletName: walletName ?? this.walletName,
      copying: copying ?? this.copying,
      submitting: submitting ?? this.submitting,
      completed: completed ?? this.completed,
      failure: identical(failure, _unchanged)
          ? this.failure
          : failure as AppFailure?,
    );
  }

  /// Releases every flow-owned reference after a confirmed durable commit.
  CreateWalletState cleared() =>
      CreateWalletState(words: const [], questions: const [], completed: true);

  @override
  bool operator ==(Object other) {
    return other is CreateWalletState &&
        listEquals(other.words, words) &&
        listEquals(other.questions, questions) &&
        mapEquals(other.quizSelections, quizSelections) &&
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
    Object.hashAll(
      quizWordNumbers.map(
        (wordNumber) => Object.hash(wordNumber, quizSelections[wordNumber]),
      ),
    ),
    walletName,
    copying,
    submitting,
    completed,
    failure,
  );
}

const _unchanged = Object();

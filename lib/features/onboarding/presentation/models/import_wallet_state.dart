import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../wallet/domain/models/models.dart';
import '../../domain/models/models.dart';

/// Flow-scoped state for importing one 12-word BIP39 wallet.
@immutable
final class ImportWalletState {
  ImportWalletState({
    List<String> words = const [],
    List<MnemonicWordStatus> wordStatuses = const [],
    this.checksumStatus = MnemonicChecksumStatus.incomplete,
    this.walletName = '',
    this.submitting = false,
    this.completed = false,
    this.failure,
  }) : words = List<String>.unmodifiable(
         words.isEmpty ? List.filled(wordCount, '') : words,
       ),
       wordStatuses = List<MnemonicWordStatus>.unmodifiable(
         wordStatuses.isEmpty
             ? List.filled(wordCount, MnemonicWordStatus.empty)
             : wordStatuses,
       ) {
    if (this.words.length != wordCount ||
        this.wordStatuses.length != wordCount) {
      throw ArgumentError('Import state requires exactly 12 word slots.');
    }
  }

  static const wordCount = 12;
  static const wordsPerPage = 4;
  static const maximumWordCharacters = 8;

  final List<String> words;
  final List<MnemonicWordStatus> wordStatuses;
  final MnemonicChecksumStatus checksumStatus;
  final String walletName;
  final bool submitting;
  final bool completed;
  final AppFailure? failure;

  /// Whether retained or uncertain wallet resources require frozen input.
  bool get requiresReconciliation => failure?.requiresReconciliation ?? false;

  bool get allWordsKnown =>
      words.every((word) => word.isNotEmpty) &&
      wordStatuses.every((status) => status == MnemonicWordStatus.valid);

  /// Whether the phrase passed both canonical-word and native checksum checks.
  bool get phraseValid =>
      allWordsKnown && checksumStatus == MnemonicChecksumStatus.valid;

  bool get canContinue =>
      !submitting &&
      !completed &&
      phraseValid &&
      (failure == null || failure!.retryable);

  String get normalizedWalletName => walletName.trim();

  bool get walletNameValid => WalletProfile.isValidName(normalizedWalletName);

  bool get canSubmit => canContinue && walletNameValid;

  String get mnemonic => words.join(' ');

  ImportWalletState copyWith({
    List<String>? words,
    List<MnemonicWordStatus>? wordStatuses,
    MnemonicChecksumStatus? checksumStatus,
    String? walletName,
    bool? submitting,
    bool? completed,
    Object? failure = _unchanged,
  }) {
    return ImportWalletState(
      words: words ?? this.words,
      wordStatuses: wordStatuses ?? this.wordStatuses,
      checksumStatus: checksumStatus ?? this.checksumStatus,
      walletName: walletName ?? this.walletName,
      submitting: submitting ?? this.submitting,
      completed: completed ?? this.completed,
      failure: identical(failure, _unchanged)
          ? this.failure
          : failure as AppFailure?,
    );
  }

  /// Releases flow-owned phrase references after a confirmed durable commit.
  ImportWalletState cleared() => ImportWalletState(completed: true);

  @override
  bool operator ==(Object other) {
    return other is ImportWalletState &&
        listEquals(other.words, words) &&
        listEquals(other.wordStatuses, wordStatuses) &&
        other.checksumStatus == checksumStatus &&
        other.walletName == walletName &&
        other.submitting == submitting &&
        other.completed == completed &&
        other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(words),
    Object.hashAll(wordStatuses),
    checksumStatus,
    walletName,
    submitting,
    completed,
    failure,
  );
}

const _unchanged = Object();

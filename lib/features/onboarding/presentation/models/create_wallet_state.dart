import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';

/// Route-scoped generated recovery phrase and provisioning state.
@immutable
final class CreateWalletState {
  CreateWalletState({
    required List<String> words,
    this.copying = false,
    this.submitting = false,
    this.completed = false,
    this.failure,
  }) : words = List<String>.unmodifiable(words) {
    final validPhrase =
        this.words.length == wordCount &&
        this.words.every((word) => word.isNotEmpty);
    if ((!completed && !validPhrase) || (completed && this.words.isNotEmpty)) {
      throw ArgumentError('Create state requires exactly 12 non-empty words.');
    }
    if ((copying && submitting) || (completed && (copying || submitting))) {
      throw ArgumentError('Create state cannot own overlapping operations.');
    }
  }

  static const wordCount = 12;

  final List<String> words;
  final bool copying;
  final bool submitting;
  final bool completed;
  final AppFailure? failure;

  /// Whether the route still owns a phrase that can be copied safely.
  bool get canCopy => !copying && !submitting && !completed;

  /// Whether retained or uncertain wallet resources require reconciliation.
  bool get requiresReconciliation => failure?.requiresReconciliation ?? false;

  /// Whether provisioning may start or explicitly retry a known-safe failure.
  bool get canSubmit => canCopy && (failure == null || failure!.retryable);

  String get mnemonic => words.join(' ');

  CreateWalletState copyWith({
    bool? copying,
    bool? submitting,
    bool? completed,
    Object? failure = _unchanged,
  }) {
    return CreateWalletState(
      words: words,
      copying: copying ?? this.copying,
      submitting: submitting ?? this.submitting,
      completed: completed ?? this.completed,
      failure: identical(failure, _unchanged)
          ? this.failure
          : failure as AppFailure?,
    );
  }

  /// Releases route-owned phrase references after a confirmed durable commit.
  CreateWalletState cleared() =>
      CreateWalletState(words: const [], completed: true);

  @override
  bool operator ==(Object other) {
    return other is CreateWalletState &&
        listEquals(other.words, words) &&
        other.copying == copying &&
        other.submitting == submitting &&
        other.completed == completed &&
        other.failure == failure;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(words),
    copying,
    submitting,
    completed,
    failure,
  );
}

const _unchanged = Object();

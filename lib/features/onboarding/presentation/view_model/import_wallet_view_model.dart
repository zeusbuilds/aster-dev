import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../../shared/feedback/feedback.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/wallet_view_model.dart';
import '../../data/repository/repository.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

part 'import_wallet_view_model.g.dart';

/// Owns route-scoped import input, SDK checksum validation, and provisioning.
@riverpod
class ImportWalletViewModel extends _$ImportWalletViewModel {
  static final _nonLetters = RegExp('[^a-z]');

  late Bip39WordList _wordList;
  var _validationRevision = 0;
  ({String mnemonic, int revision})? _pendingValidation;
  Future<void>? _validationDrain;

  @override
  Future<ImportWalletState> build() async {
    final repository = ref.watch(bip39WordListRepositoryProvider);
    final result = await repository.load();
    return switch (result) {
      AppSuccess<Bip39WordList>(:final value) => () {
        _wordList = value;
        return ImportWalletState();
      }(),
      AppFailureResult<Bip39WordList>(:final failure) =>
        throw AppFailureException(failure),
    };
  }

  /// Normalizes and validates one field without invoking the SDK per keystroke.
  void updateWord(int index, String input) {
    _updateWords(index, [input]);
  }

  /// Distributes a bounded phrase paste from [startIndex] across word fields.
  void updateWords(int startIndex, List<String> inputs) {
    _updateWords(startIndex, inputs);
  }

  void _updateWords(int startIndex, List<String> inputs) {
    final current = state.value;
    if (current == null ||
        current.submitting ||
        startIndex < 0 ||
        startIndex >= ImportWalletState.wordCount ||
        inputs.isEmpty) {
      return;
    }
    final words = [...current.words];
    final statuses = [...current.wordStatuses];
    var changed = false;
    for (
      var offset = 0;
      offset < inputs.length && startIndex + offset < words.length;
      offset += 1
    ) {
      final index = startIndex + offset;
      final normalized = _normalizeWord(inputs[offset]);
      final status = switch (normalized) {
        '' => MnemonicWordStatus.empty,
        _ when _wordList.contains(normalized) => MnemonicWordStatus.valid,
        _ => MnemonicWordStatus.invalid,
      };
      if (words[index] == normalized && statuses[index] == status) continue;
      words[index] = normalized;
      statuses[index] = status;
      changed = true;
    }
    if (!changed) return;
    final revision = ++_validationRevision;
    final next = current.copyWith(
      words: words,
      wordStatuses: statuses,
      checksumStatus: MnemonicChecksumStatus.incomplete,
      failure: null,
    );
    state = AsyncData(next);
    if (next.allWordsKnown) {
      unawaited(_scheduleChecksum(next.mnemonic, revision));
    } else {
      _pendingValidation = null;
    }
  }

  static String _normalizeWord(String input) {
    final letters = input.trim().toLowerCase().replaceAll(_nonLetters, '');
    if (letters.length <= ImportWalletState.maximumWordCharacters) {
      return letters;
    }
    return letters.substring(0, ImportWalletState.maximumWordCharacters);
  }

  /// Retries a transient native checksum failure for the unchanged phrase.
  Future<void> retryChecksum() async {
    final current = state.value;
    if (current == null ||
        current.submitting ||
        current.checksumStatus != MnemonicChecksumStatus.incomplete ||
        !current.allWordsKnown ||
        current.failure?.retryable != true) {
      return;
    }
    final revision = ++_validationRevision;
    await _scheduleChecksum(current.mnemonic, revision);
  }

  /// Provisions only after every word and the SDK checksum are valid.
  Future<bool> submit() async {
    final current = state.value;
    if (current == null || !current.canSubmit) return false;
    state = AsyncData(current.copyWith(submitting: true, failure: null));
    final result = await _createWallet(current.mnemonic);
    if (!ref.mounted) return result is AppSuccess<WalletRegistry>;
    return switch (result) {
      AppSuccess<WalletRegistry>(:final value) => () {
        state = AsyncData(current.cleared());
        unawaited(
          ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.success),
        );
        ref
            .read(walletViewModelProvider.notifier)
            .adoptCommittedRegistry(value);
        return true;
      }(),
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

  Future<void> _scheduleChecksum(String mnemonic, int revision) {
    final current = state.value;
    if (current == null || current.submitting) return Future.value();
    state = AsyncData(
      current.copyWith(
        checksumStatus: MnemonicChecksumStatus.checking,
        failure: null,
      ),
    );
    _pendingValidation = (mnemonic: mnemonic, revision: revision);
    final active = _validationDrain;
    if (active != null) return active;

    final completion = Completer<void>();
    final drain = completion.future;
    _validationDrain = drain;
    unawaited(_drainChecksumQueue(drain, completion));
    return drain;
  }

  Future<void> _drainChecksumQueue(
    Future<void> drain,
    Completer<void> completion,
  ) async {
    try {
      while (ref.mounted) {
        final request = _pendingValidation;
        if (request == null) break;
        _pendingValidation = null;
        await _validateChecksum(request.mnemonic, request.revision);
      }
    } finally {
      if (identical(_validationDrain, drain)) _validationDrain = null;
      if (!completion.isCompleted) completion.complete();
    }
  }

  Future<void> _validateChecksum(String mnemonic, int revision) async {
    final result = await _validateMnemonic(mnemonic);
    if (!ref.mounted || revision != _validationRevision) return;
    final latest = state.value;
    if (latest == null || latest.mnemonic != mnemonic) return;
    switch (result) {
      case AppSuccess<void>():
        state = AsyncData(
          latest.copyWith(
            checksumStatus: MnemonicChecksumStatus.valid,
            failure: null,
          ),
        );
      case AppFailureResult<void>(:final failure)
          when failure.code == 'wallet_mnemonic_invalid':
        state = AsyncData(
          latest.copyWith(
            checksumStatus: MnemonicChecksumStatus.invalid,
            failure: null,
          ),
        );
      case AppFailureResult<void>(:final failure):
        state = AsyncData(
          latest.copyWith(
            checksumStatus: MnemonicChecksumStatus.incomplete,
            failure: failure,
          ),
        );
    }
  }

  Future<AppResult<void>> _validateMnemonic(String mnemonic) async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return await repository.validateMnemonic(mnemonic);
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  Future<AppResult<WalletRegistry>> _createWallet(String mnemonic) async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return await repository.createFromMnemonic(
        mnemonic: mnemonic,
        name: 'Restored Wallet',
      );
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }
}

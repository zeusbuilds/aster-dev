import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../data/repository/repository.dart';

/// Retains the same lazy vocabulary owner from welcome through either form.
final walletSetupPreflightViewModelProvider =
    Provider.autoDispose<WalletSetupPreflightViewModel>((ref) {
      return WalletSetupPreflightViewModel(
        ref.watch(bip39WordListRepositoryProvider),
      );
    });

/// Checks shared, offline setup prerequisites without generating wallet secrets.
final class WalletSetupPreflightViewModel {
  const WalletSetupPreflightViewModel(this._wordList);

  final Bip39WordListRepository _wordList;

  Future<AppResult<void>> prepareRecoveryPhrase() async {
    try {
      return switch (await _wordList.load()) {
        AppSuccess<Bip39WordList>() => const AppResult.success(null),
        AppFailureResult<Bip39WordList>(:final failure) => AppResult.failure(
          failure,
        ),
      };
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }
}

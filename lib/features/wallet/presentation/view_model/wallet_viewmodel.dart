import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../models/models.dart';

part 'wallet_viewmodel.g.dart';

/// Loads wallet profile metadata and coordinates active-wallet selection.
@riverpod
class WalletViewModel extends _$WalletViewModel {
  @override
  Future<WalletState> build() => _loadWallets();

  /// Reloads wallet profiles from persistent metadata storage.
  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_loadWallets);
  }

  /// Switches the active wallet to the specified wallet ID
  ///
  /// [walletId] - The compact wallet ID to switch to
  ///
  /// Throws an error if the wallet is not found
  Future<void> switchWallet(String walletId) async {
    final current = state.requireValue;
    if (current.switchingWalletId != null ||
        current.activeWallet?.id == walletId) {
      return;
    }
    state = AsyncData(current.copyWith(switchingWalletId: walletId));
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      await repository.setActiveWallet(walletId);
      state = AsyncData(await _loadWallets());
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<WalletState> _loadWallets() async {
    final repository = await ref.read(walletRepositoryProvider.future);
    final wallets = await repository.getAllWallets();
    final activeWallet = await repository.getActiveWallet();
    return WalletState(wallets: wallets, activeWallet: activeWallet);
  }
}

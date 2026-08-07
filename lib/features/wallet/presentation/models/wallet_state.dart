import '../../data/models/wallet_model.dart';

/// Immutable wallet-profile presentation state.
class WalletState {
  const WalletState({
    this.wallets = const [],
    this.activeWallet,
    this.switchingWalletId,
  });

  final List<WalletProfile> wallets;
  final WalletProfile? activeWallet;
  final String? switchingWalletId;

  WalletState copyWith({
    List<WalletProfile>? wallets,
    Object? activeWallet = _unset,
    Object? switchingWalletId = _unset,
  }) {
    return WalletState(
      wallets: wallets == null ? this.wallets : List.unmodifiable(wallets),
      activeWallet: identical(activeWallet, _unset)
          ? this.activeWallet
          : activeWallet as WalletProfile?,
      switchingWalletId: identical(switchingWalletId, _unset)
          ? this.switchingWalletId
          : switchingWalletId as String?,
    );
  }
}

const _unset = Object();

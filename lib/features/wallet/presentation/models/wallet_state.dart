import 'package:freezed_annotation/freezed_annotation.dart';
import '../../data/models/wallet_model.dart';

part 'wallet_state.freezed.dart';

/// State model for wallet management
/// Contains the list of wallets, active wallet, loading state, and error messages
@freezed
class WalletState with _$WalletState {
  const factory WalletState({
    /// Whether wallets are currently being loaded
    @Default(false) bool isLoading,

    /// List of all available wallets
    @Default([]) List<WalletModel> wallets,

    /// Currently active/selected wallet
    WalletModel? activeWallet,

    /// Error message if any operation failed
    String? errorMessage,
  }) = _WalletState;
}

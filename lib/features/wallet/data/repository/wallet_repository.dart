import '../models/wallet_model.dart';

/// Repository interface for wallet operations
///
/// Follows dependency inversion principle
abstract class WalletRepository {
  /// Get all wallets
  Future<List<WalletModel>> getAllWallets();

  /// Get active wallet
  Future<WalletModel?> getActiveWallet();

  /// Get wallet by ID
  Future<WalletModel?> getWalletById(String walletId);

  /// Save a new wallet (creates WalletModel and stores seed phrase)
  Future<WalletModel> saveWallet(String seedPhrase);

  /// Get seed phrase for a wallet (from secure storage)
  Future<String?> getSeedPhrase(String walletId);

  /// Switch active wallet
  Future<void> setActiveWallet(String walletId);

  /// Update wallet metadata
  Future<void> updateWallet(WalletModel wallet);

  /// Delete wallet (removes from database and secure storage)
  Future<void> deleteWallet(String walletId);

  /// Check if wallet exists
  Future<bool> walletExists(String walletId);
}

import '../../../../core/core.dart';
import '../../../../objectbox.g.dart';
import '../models/models.dart';

/// Repository for wallet operations.
///
/// Handles persistence of wallets in ObjectBox, secure storage for seed
/// phrases, and related preference flags.
class WalletRepository {
  WalletRepository({
    required DatabaseService databaseService,
    required SecureStorageService secureStorageService,
    required PreferencesService preferencesService,
  }) : _databaseService = databaseService,
       _secureStorageService = secureStorageService,
       _preferencesService = preferencesService;

  final DatabaseService _databaseService;
  final SecureStorageService _secureStorageService;
  final PreferencesService _preferencesService;

  Box<WalletModel> get _walletBox => _databaseService.box<WalletModel>();

  /// Retrieves all wallets from the database.
  ///
  /// Returns a list of all `WalletModel` instances.
  Future<List<WalletModel>> getAllWallets() async {
    return _walletBox.getAll();
  }

  /// Gets the currently active wallet.
  ///
  /// Returns the active wallet if found, null if no active wallet is set.
  Future<WalletModel?> getActiveWallet() async {
    final activeWalletId = await _preferencesService.getString(
      StorageKeys.activeWalletId,
    );

    if (activeWalletId == null) {
      return null;
    }

    return getWalletById(activeWalletId);
  }

  /// Gets a wallet by its ID.
  ///
  /// [walletId] - The wallet ID (can be display or compact format).
  ///
  /// Returns the wallet if found, null otherwise.
  Future<WalletModel?> getWalletById(String walletId) async {
    final compactId = walletId.replaceAll(' ', '');
    final query = _walletBox
        .query(WalletModel_.compactWalletId.equals(compactId))
        .build();

    final wallet = query.findFirst();
    query.close();

    return wallet;
  }

  /// Saves a new wallet from a seed phrase.
  ///
  /// [seedPhrase] - The 12 or 24 word seed phrase.
  ///
  /// Validates seed phrase, creates wallet model, saves to database and secure
  /// storage.
  ///
  /// Sets as active if it's the first wallet.
  ///
  /// Throws [ArgumentError] if seed phrase is invalid.
  ///
  /// Throws [StateError] if wallet already exists.
  Future<WalletModel> saveWallet(String seedPhrase) async {
    // Validate seed phrase format (12 or 24 words)
    final words = seedPhrase.trim().split(' ');
    if (words.length != 12 && words.length != 24) {
      throw ArgumentError('Seed phrase must be 12 or 24 words');
    }

    // Generate wallet model
    final wallet = WalletModel.fromSeedPhrase(seedPhrase);

    // Check if wallet already exists
    if (await walletExists(wallet.compactWalletId)) {
      throw StateError('Wallet with this seed phrase already exists');
    }

    // Save to database
    _walletBox.put(wallet);

    // Save seed phrase to secure storage
    await _secureStorageService.write(
      key: StorageKeys.walletSeedKey(wallet.compactWalletId),
      value: seedPhrase,
    );

    // If this is the first wallet, set it as active
    final allWallets = await getAllWallets();
    if (allWallets.length == 1) {
      await setActiveWallet(wallet.compactWalletId);
    }

    return wallet;
  }

  /// Retrieves the seed phrase for a wallet from secure storage.
  ///
  /// [walletId] - The wallet ID (can be display or compact format).
  ///
  /// Returns the seed phrase if found, null otherwise.
  Future<String?> getSeedPhrase(String walletId) async {
    final compactId = walletId.replaceAll(' ', '');
    return await _secureStorageService.read(
      key: StorageKeys.walletSeedKey(compactId),
    );
  }

  /// Sets a wallet as the active wallet.
  ///
  /// [walletId] - The wallet ID to activate.
  ///
  /// Deactivates all other wallets and updates preferences.
  ///
  /// Throws [StateError] if wallet is not found.
  Future<void> setActiveWallet(String walletId) async {
    final compactId = walletId.replaceAll(' ', '');

    // Get wallet
    final wallet = await getWalletById(compactId);
    if (wallet == null) {
      throw StateError('Wallet not found: $walletId');
    }

    // Deactivate all wallets
    final allWallets = await getAllWallets();
    for (final w in allWallets) {
      if (w.isActive) {
        _walletBox.put(w.copyWith(isActive: false, updatedAt: DateTime.now()));
      }
    }

    // Activate selected wallet
    _walletBox.put(wallet.copyWith(isActive: true, updatedAt: DateTime.now()));

    // Update preferences
    await _preferencesService.setString(StorageKeys.activeWalletId, compactId);
  }

  /// Updates wallet metadata in the database.
  ///
  /// [wallet] - The wallet model with updated fields.
  ///
  /// Updates the `updatedAt` timestamp automatically.
  Future<void> updateWallet(WalletModel wallet) async {
    _walletBox.put(wallet.copyWith(updatedAt: DateTime.now()));
  }

  /// Deletes a wallet from database and secure storage.
  ///
  /// [walletId] - The wallet ID to delete.
  ///
  /// Switches to another wallet if deleting the active wallet.
  ///
  /// Throws [StateError] if wallet not found or trying to delete the only
  /// wallet.
  Future<void> deleteWallet(String walletId) async {
    final compactId = walletId.replaceAll(' ', '');

    // Get wallet
    final wallet = await getWalletById(compactId);
    if (wallet == null) {
      throw StateError('Wallet not found: $walletId');
    }

    // Don't allow deleting active wallet if it's the only wallet
    final allWallets = await getAllWallets();
    if (wallet.isActive && allWallets.length == 1) {
      throw StateError('Cannot delete the only wallet');
    }

    // If deleting active wallet, switch to another
    if (wallet.isActive && allWallets.length > 1) {
      final otherWallet = allWallets.firstWhere((w) => w.id != wallet.id);
      await setActiveWallet(otherWallet.compactWalletId);
    }

    // Remove from database
    _walletBox.remove(wallet.id);

    // Remove seed phrase from secure storage
    await _secureStorageService.delete(
      key: StorageKeys.walletSeedKey(compactId),
    );
  }

  /// Checks if a wallet exists in the database.
  ///
  /// [walletId] - The wallet ID to check.
  ///
  /// Returns true if wallet exists, false otherwise.
  Future<bool> walletExists(String walletId) async {
    final wallet = await getWalletById(walletId);
    return wallet != null;
  }
}

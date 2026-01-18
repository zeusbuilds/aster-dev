import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/core.dart';
import '../models/models.dart';

part 'wallet_viewmodel.g.dart';

/// ViewModel for managing wallet state and operations
/// Handles loading wallets, switching active wallet, adding new wallets, and retrieving seed phrases
@riverpod
class WalletViewModel extends _$WalletViewModel {
  @override
  WalletState build() {
    // Load wallets asynchronously after state is initialized
    Future.microtask(() => loadWallets());
    return const WalletState();
  }

  /// Loads all wallets and sets the active wallet
  /// Updates the state with the loaded wallets and active wallet information
  Future<void> loadWallets() async {
    // ignore: avoid_print
    print('WalletViewModel: loadWallets called');
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final repository = ref.read(walletRepositoryProvider);
      final wallets = await repository.getAllWallets();
      // ignore: avoid_print
      print('WalletViewModel: Loaded ${wallets.length} wallets');
      final activeWallet = await repository.getActiveWallet();
      // ignore: avoid_print
      print('WalletViewModel: Active wallet: ${activeWallet?.name ?? 'null'}');

      state = state.copyWith(
        wallets: wallets,
        activeWallet: activeWallet,
        isLoading: false,
      );
      // ignore: avoid_print
      print(
        'WalletViewModel: State updated - isLoading: false, wallets: ${state.wallets.length}, activeWallet: ${state.activeWallet?.name}',
      );
    } catch (e) {
      // ignore: avoid_print
      print('WalletViewModel: Error loading wallets: $e');
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Switches the active wallet to the specified wallet ID
  ///
  /// [walletId] - The compact wallet ID to switch to
  /// Throws an error if the wallet is not found
  Future<void> switchWallet(String walletId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final repository = ref.read(walletRepositoryProvider);
      await repository.setActiveWallet(walletId);

      // Reload wallets to get updated state
      await loadWallets();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  /// Adds a new wallet from a seed phrase
  ///
  /// [seedPhrase] - The 12 or 24 word seed phrase to create the wallet from
  /// Throws an error if the seed phrase is invalid or wallet already exists
  Future<void> addWallet(String seedPhrase) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final repository = ref.read(walletRepositoryProvider);
      await repository.saveWallet(seedPhrase);

      // Reload wallets
      await loadWallets();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  /// Retrieves the seed phrase for a specific wallet from secure storage
  ///
  /// [walletId] - The compact wallet ID to get the seed phrase for
  /// Returns the seed phrase if found, null otherwise
  Future<String?> getSeedPhrase(String walletId) async {
    try {
      final repository = ref.read(walletRepositoryProvider);
      return await repository.getSeedPhrase(walletId);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return null;
    }
  }
}

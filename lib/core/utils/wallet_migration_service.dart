import '../../features/wallet/data/repository/repository.dart';

/// Service to migrate hardcoded test wallets to persistent storage
class WalletMigrationService {
  WalletMigrationService(this._repository);

  final WalletRepository _repository;

  /// Hardcoded test wallets to migrate
  /// These are the two wallets that were previously hardcoded in the app
  static const List<String> _testWallets = [
    'joy amount topple panic struggle crystal mammal guilt nature mandate uniform demise',
    'empower useless coach patch turkey easily stamp suit coyote fragile finger embrace',
  ];

  /// Migrate hardcoded test wallets if no wallets exist
  Future<void> migrateIfNeeded() async {
    // ignore: avoid_print
    print('WalletMigrationService: Starting migration check');
    final wallets = await _repository.getAllWallets();
    // ignore: avoid_print
    print('WalletMigrationService: Found ${wallets.length} existing wallets');

    // Only migrate if no wallets exist
    if (wallets.isNotEmpty) {
      // ignore: avoid_print
      print(
        'WalletMigrationService: Wallets already exist, skipping migration',
      );
      return;
    }

    // ignore: avoid_print
    print('WalletMigrationService: No wallets found, starting migration');
    // Migrate each test wallet
    for (var i = 0; i < _testWallets.length; i++) {
      try {
        // ignore: avoid_print
        print(
          'WalletMigrationService: Migrating wallet ${i + 1}/${_testWallets.length}',
        );
        await _repository.saveWallet(_testWallets[i]);
        // ignore: avoid_print
        print('WalletMigrationService: Successfully migrated wallet ${i + 1}');
      } catch (e) {
        // Log error but continue migration
        // ignore: avoid_print
        print('WalletMigrationService: Failed to migrate wallet ${i + 1}: $e');
      }
    }

    // Set first wallet as active
    final migratedWallets = await _repository.getAllWallets();
    // ignore: avoid_print
    print(
      'WalletMigrationService: Migration complete, ${migratedWallets.length} wallets migrated',
    );
    if (migratedWallets.isNotEmpty) {
      // ignore: avoid_print
      print(
        'WalletMigrationService: Setting first wallet as active: ${migratedWallets.first.compactWalletId}',
      );
      await _repository.setActiveWallet(migratedWallets.first.compactWalletId);
      // ignore: avoid_print
      print('WalletMigrationService: Active wallet set successfully');
    }
  }
}

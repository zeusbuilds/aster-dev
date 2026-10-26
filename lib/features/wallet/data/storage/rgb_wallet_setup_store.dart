import '../../../../core/errors/errors.dart';
import 'wallet_registry_document_store.dart';
import 'wallet_scoped_data_removal.dart';
import 'wallet_storage_security.dart';

/// Private crash-tolerant wallet-scoped financial-operation journal.
abstract interface class RgbWalletSetupStore {
  Future<String?> read(String walletId);
  Future<void> write(String walletId, String document);
}

final class IoRgbWalletSetupStore
    implements RgbWalletSetupStore, WalletScopedDataRemoval {
  const IoRgbWalletSetupStore(this.rootPath, this.security);
  final String rootPath;
  final WalletStorageSecurity security;

  @override
  Future<void> removeWallet(String walletId) =>
      removeWalletScopedDirectory(rootPath, walletId, security);

  Future<IoWalletRegistryDocumentStore> _wallet(String walletId) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(walletId)) {
      throw const StoredDataCorruptionException();
    }
    await security.prepareRoot(rootPath);
    return IoWalletRegistryDocumentStore(
      '$rootPath/$walletId',
      security,
      rejectCorruptSlots: true,
    );
  }

  @override
  Future<String?> read(String walletId) async =>
      (await _wallet(walletId)).read();
  @override
  Future<void> write(String walletId, String document) async =>
      (await _wallet(walletId)).write(document);
}

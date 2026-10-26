import 'dart:io';

import '../../../../core/errors/errors.dart';
import 'wallet_registry_document_store.dart';
import 'wallet_scoped_data_removal.dart';
import 'wallet_storage_security.dart';

/// Permanent accepted-payment receipts, separate from the latest intent fence.
abstract interface class WalletPaymentReceiptStore {
  Future<Map<String, String>> readAll(String walletId);
  Future<void> writeReceipt(
    String walletId,
    String receiptKey,
    String document,
  );
}

/// Immutable, private receipt documents with the financial journal's strict
/// checksum and durable-commit policy. A newer send never replaces an old key.
final class IoWalletPaymentReceiptStore
    implements WalletPaymentReceiptStore, WalletScopedDataRemoval {
  const IoWalletPaymentReceiptStore(this.rootPath, this.security);

  final String rootPath;
  final WalletStorageSecurity security;

  @override
  Future<void> removeWallet(String walletId) =>
      removeWalletScopedDirectory(rootPath, walletId, security);

  Future<String> _wallet(String walletId) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(walletId)) {
      throw const StoredDataCorruptionException();
    }
    await _requireDirectoryOrMissing(rootPath);
    await security.prepareRoot(rootPath);
    final path = '$rootPath/$walletId';
    await _requireDirectoryOrMissing(path);
    if (await Directory(path).exists()) {
      await security.verifyDirectory(path);
    } else {
      // Native prepareRoot creates only one level and requires its secure
      // parent to exist. Prepare the wallet before the per-receipt child.
      await security.prepareRoot(path);
    }
    return path;
  }

  @override
  Future<Map<String, String>> readAll(String walletId) async {
    final path = await _wallet(walletId);
    if (!await Directory(path).exists()) return const {};
    await security.verifyDirectory(path);
    final records = <String, String>{};
    await for (final entry in Directory(path).list(followLinks: false)) {
      final key = entry.path.split(Platform.pathSeparator).last;
      _requireKey(key);
      await _requireDirectoryOrMissing(entry.path);
      final value = await _document(entry.path).read();
      if (value == null) throw const StoredDataCorruptionException();
      records[key] = value;
    }
    return Map.unmodifiable(records);
  }

  @override
  Future<void> writeReceipt(
    String walletId,
    String receiptKey,
    String document,
  ) async {
    _requireKey(receiptKey);
    final path = '${await _wallet(walletId)}/$receiptKey';
    await _requireDirectoryOrMissing(path);
    final store = _document(path);
    final existing = await store.read();
    if (existing != null) {
      if (existing != document) throw const StoredDataCorruptionException();
      return;
    }
    await store.write(document);
  }

  IoWalletRegistryDocumentStore _document(String path) =>
      IoWalletRegistryDocumentStore(path, security, rejectCorruptSlots: true);

  static void _requireKey(String key) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw const StoredDataCorruptionException();
    }
  }

  static Future<void> _requireDirectoryOrMissing(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw const StoredDataCorruptionException();
    }
  }
}

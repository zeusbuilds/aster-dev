import 'dart:io';

import '../../../../core/errors/errors.dart';
import 'wallet_storage_security.dart';

/// Private wallet data erased only after its durable deletion was authorized.
abstract interface class WalletScopedDataRemoval {
  Future<void> removeWallet(String walletId);
}

/// Never follows links or accepts a path supplied by product input.
Future<void> removeWalletScopedDirectory(
  String rootPath,
  String walletId,
  WalletStorageSecurity security,
) async {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(walletId)) {
    throw const StoredDataCorruptionException();
  }
  final rootType = await FileSystemEntity.type(rootPath, followLinks: false);
  if (rootType == FileSystemEntityType.notFound) return;
  if (rootType != FileSystemEntityType.directory) {
    throw const StoredDataCorruptionException();
  }
  await security.verifyDirectory(rootPath);
  final path = '$rootPath/$walletId';
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    // The previous attempt may have removed the child but failed its fsync.
    if (security is WalletStorageDurability) {
      await (security as WalletStorageDurability).flushDirectory(rootPath);
    }
    return;
  }
  if (type != FileSystemEntityType.directory) {
    throw const StoredDataCorruptionException();
  }
  await security.verifyDirectory(path);
  await Directory(path).delete(recursive: true);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException('Wallet metadata removal did not complete.');
  }
  if (security is WalletStorageDurability) {
    await (security as WalletStorageDurability).flushDirectory(rootPath);
  }
}

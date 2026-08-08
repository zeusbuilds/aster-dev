import 'dart:io';

import '../storage/wallet_storage_security.dart';

/// Owns native wallet directories beneath one app-support root.
abstract interface class WalletDirectoryManager {
  Future<String> create(String walletId, {required String storageToken});
  Future<String> open(String walletId, {required String storageToken});
  Future<void> remove(String walletId, {required String storageToken});
  Future<Set<String>> walletIds();
}

final class IoWalletDirectoryManager implements WalletDirectoryManager {
  const IoWalletDirectoryManager(this.rootPath, this._security);

  final String rootPath;
  final WalletStorageSecurity _security;

  @override
  Future<String> create(String walletId, {required String storageToken}) async {
    _validateWalletId(walletId);
    _validateStorageToken(storageToken);
    await _security.prepareRoot(rootPath);
    final directory = _directory(walletId);
    await _security.createDirectory(directory.path);
    try {
      await _security.replaceTextFile(
        _ownershipFile(directory).path,
        storageToken,
      );
    } catch (error) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        throw FileSystemException(
          'Wallet directory ownership marker could not be created or rolled back.',
          directory.path,
        );
      }
      rethrow;
    }
    return directory.path;
  }

  @override
  Future<String> open(String walletId, {required String storageToken}) async {
    _validateWalletId(walletId);
    _validateStorageToken(storageToken);
    await _security.verifyDirectory(rootPath);
    final directory = _directory(walletId);
    if (!await directory.exists()) {
      throw FileSystemException('Wallet directory does not exist.');
    }
    await _security.verifyDirectory(directory.path);
    await _verifyOwnership(directory, storageToken);
    return directory.path;
  }

  @override
  Future<void> remove(String walletId, {required String storageToken}) async {
    _validateWalletId(walletId);
    _validateStorageToken(storageToken);
    final root = Directory(rootPath);
    if (await root.exists()) await _security.verifyDirectory(rootPath);
    final directory = _directory(walletId);
    if (await directory.exists()) {
      await _security.verifyDirectory(directory.path);
      await _verifyOwnership(directory, storageToken);
      await directory.delete(recursive: true);
    }
  }

  @override
  Future<Set<String>> walletIds() async {
    final root = Directory(rootPath);
    if (!await root.exists()) return const <String>{};
    await _security.verifyDirectory(rootPath);
    final ids = <String>{};
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) {
        throw FileSystemException(
          'Wallet storage contains an unexpected entry.',
          rootPath,
        );
      }
      final walletId = entity.path.split(Platform.pathSeparator).last;
      if (!_walletIdPattern.hasMatch(walletId)) {
        throw FileSystemException(
          'Wallet storage contains an invalid directory.',
          entity.path,
        );
      }
      await _security.verifyDirectory(entity.path);
      ids.add(walletId);
    }
    return Set<String>.unmodifiable(ids);
  }

  Directory _directory(String walletId) => Directory(
    '${Directory(rootPath).path}${Platform.pathSeparator}$walletId',
  );

  static File _ownershipFile(Directory directory) =>
      File('${directory.path}${Platform.pathSeparator}.utexo-storage-owner');

  Future<void> _verifyOwnership(
    Directory directory,
    String storageToken,
  ) async {
    final marker = _ownershipFile(directory);
    await _security.verifyFile(marker.path);
    if (!await marker.exists() || await marker.length() > 64) {
      throw FileSystemException(
        'Wallet directory ownership could not be verified.',
        directory.path,
      );
    }
    if (await marker.readAsString() != storageToken) {
      throw FileSystemException(
        'Wallet directory ownership could not be verified.',
        directory.path,
      );
    }
  }

  static void _validateWalletId(String walletId) {
    if (!_walletIdPattern.hasMatch(walletId)) {
      throw ArgumentError.value(walletId, 'walletId', 'Has an invalid shape.');
    }
  }

  static final _walletIdPattern = RegExp(r'^[a-f0-9]{32}$');

  static void _validateStorageToken(String storageToken) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(storageToken)) {
      throw ArgumentError.value(
        storageToken,
        'storageToken',
        'Has an invalid shape.',
      );
    }
  }
}

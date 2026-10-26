import 'dart:io';

import 'package:flutter/services.dart';

/// Native storage policy required before the SDK may open wallet files.
///
/// Production implementations constrain paths to the app sandbox, reject
/// symbolic links, enforce owner-only directory permissions, and apply the
/// platform's backup and data-protection policy.
abstract interface class WalletStorageSecurity {
  /// Creates or repairs an app-owned wallet storage root.
  Future<void> prepareRoot(String path);

  /// Creates a new owner-only child directory and fails if it already exists.
  Future<void> createDirectory(String path);

  /// Verifies that an existing directory still satisfies the native policy.
  Future<void> verifyDirectory(String path);

  /// Verifies that an existing wallet metadata file is regular and owner-only.
  Future<void> verifyFile(String path);

  /// Durably replaces a non-secret metadata file in one atomic commit.
  ///
  /// Implementations flush the new file, atomically rename it in place, and
  /// flush the containing directory before returning.
  Future<void> replaceTextFile(String path, String contents);
}

/// Native directory durability required before a deletion marker is retired.
/// Fsync the surviving parent after renaming or removing its owned child.
abstract interface class WalletStorageDurability {
  Future<void> flushDirectory(String path);
}

/// Method-channel adapter for the app's iOS and Android storage policy.
final class PlatformWalletStorageSecurity
    implements WalletStorageSecurity, WalletStorageDurability {
  const PlatformWalletStorageSecurity();

  static const _channel = MethodChannel('com.aster.wallet/storage_security');

  @override
  Future<void> prepareRoot(String path) => _invoke('prepareRoot', path);

  @override
  Future<void> createDirectory(String path) => _invoke('createDirectory', path);

  @override
  Future<void> verifyDirectory(String path) => _invoke('verifyDirectory', path);

  @override
  Future<void> verifyFile(String path) => _invoke('verifyFile', path);

  @override
  Future<void> flushDirectory(String path) => _invoke('flushDirectory', path);

  @override
  Future<void> replaceTextFile(String path, String contents) =>
      _invoke('replaceTextFile', path, contents: contents);

  static Future<void> _invoke(
    String method,
    String path, {
    String? contents,
  }) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      throw UnsupportedError(
        'Wallet storage security is supported only on iOS and Android.',
      );
    }
    try {
      await _channel.invokeMethod<void>(method, {
        'path': path,
        'contents': ?contents,
      });
    } on PlatformException catch (error) {
      Error.throwWithStackTrace(
        FileSystemException(
          'Wallet storage policy failed (${error.code}).',
          path,
        ),
        error.stacktrace == null
            ? StackTrace.current
            : StackTrace.fromString(error.stacktrace!),
      );
    } on MissingPluginException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        FileSystemException('Wallet storage policy is unavailable.', path),
        stackTrace,
      );
    }
  }
}

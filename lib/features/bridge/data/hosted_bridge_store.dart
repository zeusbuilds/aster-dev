import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:reown_core/store/i_store.dart';

import '../../../core/storage/secure_storage_service.dart';

/// WalletConnect state includes relay keys, proposals and private payment
/// requests. A storage failure closes the bridge instead of falling back to
/// shared preferences. This namespace is separate from the wallet secrets.
final class HostedBridgeStore implements IStore<Map<String, dynamic>> {
  HostedBridgeStore({SecureKeyValueStore? storage})
    : _storage =
          storage ??
          SecureStorageService(
            storage: const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'com.aster.wallet.devbridge.walletconnect',
                accessibility: KeychainAccessibility.unlocked_this_device,
                synchronizable: false,
              ),
              aOptions: AndroidOptions(
                storageNamespace: 'aster_devbridge_walletconnect',
                resetOnError: false,
                migrateOnAlgorithmChange: true,
                migrateWithBackup: false,
                keyCipherAlgorithm:
                    KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
                storageCipherAlgorithm:
                    StorageCipherAlgorithm.AES_GCM_NoPadding,
              ),
            ),
          );

  final SecureKeyValueStore _storage;
  final _documents = <String, String>{};
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  static const _maxDocument = 2 * 1024 * 1024;
  static const _maxTotal = 8 * 1024 * 1024;
  static const _maxKeys = 128;

  @override
  String get storagePrefix => 'aster.devbridge.wc.v1.';

  @override
  Future<void> init() => _initializing ??= _load();

  Future<void> _load() async {
    final names = (await _storage.keys())
        .where((key) => key.startsWith(storagePrefix))
        .toList();
    if (names.length > _maxKeys) {
      throw const FormatException('Bridge storage limit exceeded.');
    }
    var total = 0;
    for (final name in names) {
      final key = utf8.decode(
        base64Url.decode(name.substring(storagePrefix.length)),
      );
      final value = await _storage.read(key: name);
      if (_name(key) != name ||
          value == null ||
          value.length > _maxDocument ||
          (total += value.length) > _maxTotal ||
          jsonDecode(value) is! Map<String, dynamic>) {
        throw const FormatException('Invalid bridge storage.');
      }
      _documents[key] = value;
    }
  }

  String _name(String key) {
    if (key.isEmpty || key.length > 256 || key.contains('\u0000')) {
      throw const FormatException('Invalid bridge storage key.');
    }
    return '$storagePrefix${base64Url.encode(utf8.encode(key))}';
  }

  Future<void> _serialize(Future<void> Function() action) {
    final next = _writes.then((_) async {
      await init();
      await action();
    });
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  Map<String, dynamic>? get(String key) {
    final data = _documents[key];
    return data == null ? null : jsonDecode(data) as Map<String, dynamic>;
  }

  @override
  bool has(String key) => _documents.containsKey(key);

  @override
  List<String> get keys => List.unmodifiable(_documents.keys);

  @override
  List<Map<String, dynamic>> get values => [for (final key in keys) get(key)!];

  @override
  Map<String, Map<String, dynamic>> get map => {
    for (final key in keys) key: get(key)!,
  };

  @override
  List<Map<String, dynamic>> getAll() => values;

  @override
  Future<void> set(String key, Map<String, dynamic> value) =>
      _write(key, value, requireExisting: false);

  @override
  Future<void> update(String key, Map<String, dynamic> value) =>
      _write(key, value, requireExisting: true);

  Future<void> _write(
    String key,
    Map<String, dynamic> value, {
    required bool requireExisting,
  }) async {
    final encoded = jsonEncode(value);
    if (encoded.length > _maxDocument) {
      throw const FormatException('Bridge storage limit exceeded.');
    }
    await _serialize(() async {
      if (requireExisting && !has(key)) {
        throw StateError('Missing bridge storage entry.');
      }
      if ((!has(key) && _documents.length >= _maxKeys) ||
          encoded.length +
                  _documents.entries
                      .where((e) => e.key != key)
                      .fold(0, (total, e) => total + e.value.length) >
              _maxTotal) {
        throw const FormatException('Bridge storage limit exceeded.');
      }
      await _storage.write(key: _name(key), value: encoded);
      _documents[key] = encoded;
    });
  }

  @override
  Future<void> delete(String key) => _serialize(() async {
    await _storage.delete(key: _name(key));
    _documents.remove(key);
  });

  @override
  Future<void> deleteAll() => _serialize(() async {
    for (final key in keys) {
      await _storage.delete(key: _name(key));
      _documents.remove(key);
    }
  });
}

import 'dart:convert';
import 'dart:math';

/// Generates identifiers and native database passwords from the OS CSPRNG.
abstract interface class WalletIdentityGenerator {
  String newWalletId();
  String newStorageToken();
  String newDatabasePassword();
}

final class SecureWalletIdentityGenerator implements WalletIdentityGenerator {
  SecureWalletIdentityGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String newWalletId() => _hex(_bytes(16));

  @override
  String newStorageToken() => _hex(_bytes(16));

  @override
  String newDatabasePassword() => base64UrlEncode(_bytes(32));

  List<int> _bytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256), growable: false);

  static String _hex(List<int> bytes) =>
      bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

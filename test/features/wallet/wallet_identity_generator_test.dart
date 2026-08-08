import 'dart:convert';
import 'dart:math';

import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generates bounded independent identifiers and database secrets', () {
    final generator = SecureWalletIdentityGenerator(random: Random(7));

    final walletId = generator.newWalletId();
    final storageToken = generator.newStorageToken();
    final databasePassword = generator.newDatabasePassword();

    expect(walletId, matches(RegExp(r'^[a-f0-9]{32}$')));
    expect(storageToken, matches(RegExp(r'^[a-f0-9]{32}$')));
    expect(storageToken, isNot(walletId));
    expect(base64Url.decode(databasePassword), hasLength(32));
  });
}

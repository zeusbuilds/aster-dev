import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

final class _SyncWallet extends Mock implements UtexoWallet {}

RgbWalletEngine _engine(UtexoWallet wallet) => RgbWalletEngine(
  wallet,
  const WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
  ),
  UtexoUnlockConfig(),
);

void main() {
  test(
    'sync remains pending until RGB consignments and acknowledgements refresh',
    () async {
      final wallet = _SyncWallet();
      final chain = Completer<void>();
      final rgb = Completer<void>();
      when(() => wallet.syncWallet()).thenAnswer((_) => chain.future);
      when(() => wallet.refreshWallet()).thenAnswer((_) => rgb.future);
      var completed = false;
      final sync = _engine(wallet).sync().then((_) => completed = true);

      verifyNever(() => wallet.refreshWallet());
      chain.complete();
      await Future<void>.delayed(Duration.zero);
      verify(() => wallet.refreshWallet()).called(1);
      expect(completed, isFalse);
      rgb.complete();
      await sync;
      expect(completed, isTrue);
    },
  );

  test(
    'RGB refresh failure cannot be reported as a successful wallet sync',
    () async {
      final wallet = _SyncWallet();
      const failure = NetworkError('redacted transport failure');
      when(() => wallet.syncWallet()).thenAnswer((_) async {});
      when(() => wallet.refreshWallet()).thenThrow(failure);

      await expectLater(_engine(wallet).sync(), throwsA(same(failure)));
    },
  );
}

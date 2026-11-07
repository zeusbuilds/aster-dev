import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wallet_fakes.dart';

void main() {
  test(
    'qualification constructor admits Debug only, never Profile or Release',
    () {
      const expected = String.fromEnvironment(
        'ASTER_QA_EXPECT_MODE',
        defaultValue: 'debug',
      );
      expect(kDebugMode, expected == 'debug');
      expect(kProfileMode, expected == 'profile');
      expect(kReleaseMode, expected == 'release');
      WalletRuntime construct() => WalletRuntime.forQualification(
        FakeWalletEngineFactory([]),
        IoWalletDirectoryManager(
          '/private/aster_full_wallet_qa/run_001/native',
          MemoryWalletStorageSecurity(),
        ),
        WalletSecretStore(MemorySecureStore()),
        const WalletServiceConfiguration(
          backend: WalletBackend.rgbL1,
          environment: BlockchainEnvironment.regtest,
          sdkNetwork: 'regtest',
          indexerUrl: 'http://127.0.0.1:49794',
          rgbTransportProxy: 'rpc://127.0.0.1:49790/json-rpc',
        ),
      );
      if (kDebugMode) {
        final runtime = construct();
        addTearDown(runtime.dispose);
      } else {
        expect(construct, throwsArgumentError);
      }
      expect(WalletBackend.rgbL1.activationAllowed, isFalse);
    },
  );
}

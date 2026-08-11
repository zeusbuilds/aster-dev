import 'package:aster/core/core.dart';
import 'package:aster/features/swap/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';

void main() {
  test(
    'selects only configured typed targets and reverses atomically',
    () async {
      final harness = await PaymentFlowTestHarness.create();
      addTearDown(harness.dispose);
      final initial = await harness.container.read(
        swapViewModelProvider.future,
      );
      final notifier = harness.container.read(swapViewModelProvider.notifier);

      expect(initial.capabilities, hasLength(4));
      expect(initial.from, WalletPaymentTarget.bitcoinOnchain);
      expect(initial.to, WalletPaymentTarget.bitcoinLightning);
      expect(notifier.selectTo(WalletPaymentTarget.usdtOnchain), isFalse);
      expect(notifier.reverse(), isTrue);
      final reversed = harness.container
          .read(swapViewModelProvider)
          .requireValue;
      expect(reversed.from, WalletPaymentTarget.bitcoinLightning);
      expect(reversed.to, WalletPaymentTarget.bitcoinOnchain);
    },
  );

  test(
    'prefers configured RGB USDT without deriving contract identity',
    () async {
      final harness = await PaymentFlowTestHarness.create(
        services: const WalletServiceConfiguration(
          environment: BlockchainEnvironment.regtest,
          sdkNetwork: 'regtest',
          usdtAsset: RgbAssetConfiguration(
            contractId: 'deployment-owned-contract',
            precision: 6,
          ),
        ),
      );
      addTearDown(harness.dispose);

      final state = await harness.container.read(swapViewModelProvider.future);

      expect(state.to, WalletPaymentTarget.usdtOnchain);
      expect(state.capabilities.every((item) => item.isAvailable), isTrue);
    },
  );
}

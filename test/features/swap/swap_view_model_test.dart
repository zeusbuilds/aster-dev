import 'package:aster/core/core.dart';
import 'package:aster/features/swap/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';

void main() {
  test('one configured target remains a non-executable preview', () async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(harness.dispose);
    final initial = harness.container.read(swapViewModelProvider);
    final notifier = harness.container.read(swapViewModelProvider.notifier);

    expect(initial.capabilities, hasLength(4));
    expect(initial.from, WalletPaymentTarget.bitcoinOnchain);
    expect(initial.to, WalletPaymentTarget.usdtOnchain);
    expect(initial.canReverse, isFalse);
    expect(notifier.selectTo(WalletPaymentTarget.usdtOnchain), isFalse);
    expect(notifier.selectTo(WalletPaymentTarget.bitcoinOnchain), isFalse);
    expect(notifier.reverse(), isFalse);
    final reversed = harness.container.read(swapViewModelProvider);
    expect(reversed, initial);
  });

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
            requiresEvmValidation: false,
          ),
        ),
      );
      addTearDown(harness.dispose);

      final state = harness.container.read(swapViewModelProvider);

      expect(state.to, WalletPaymentTarget.usdtOnchain);
      expect(state.capabilities.map((item) => item.isAvailable), [
        true,
        false,
        true,
        false,
      ]);
      expect(state.canReverse, isTrue);
      final notifier = harness.container.read(swapViewModelProvider.notifier);
      expect(notifier.selectTo(WalletPaymentTarget.bitcoinLightning), isFalse);
      expect(notifier.reverse(), isTrue);
      final reversed = harness.container.read(swapViewModelProvider);
      expect(reversed.from, WalletPaymentTarget.usdtOnchain);
      expect(reversed.to, WalletPaymentTarget.bitcoinOnchain);
    },
  );
}

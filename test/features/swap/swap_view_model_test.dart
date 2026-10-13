import 'package:aster/core/core.dart';
import 'package:aster/features/swap/presentation/models/models.dart';
import 'package:aster/features/swap/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';

void main() {
  test('one configured target remains a non-executable preview', () async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(harness.dispose);
    final initial = await harness.container.read(swapViewModelProvider.future);
    final notifier = harness.container.read(swapViewModelProvider.notifier);

    expect(initial.capabilities, hasLength(4));
    expect(initial.from, WalletPaymentTarget.bitcoinOnchain);
    expect(initial.to, WalletPaymentTarget.usdtOnchain);
    expect(initial.canReverse, isFalse);
    expect(notifier.selectTo(WalletPaymentTarget.usdtOnchain), isFalse);
    expect(notifier.selectTo(WalletPaymentTarget.bitcoinOnchain), isFalse);
    expect(notifier.reverse(), isFalse);
    final reversed = harness.container.read(swapViewModelProvider).requireValue;
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
          ),
        ),
      );
      addTearDown(harness.dispose);

      final state = await harness.container.read(swapViewModelProvider.future);

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
      final reversed = harness.container
          .read(swapViewModelProvider)
          .requireValue;
      expect(reversed.from, WalletPaymentTarget.usdtOnchain);
      expect(reversed.to, WalletPaymentTarget.bitcoinOnchain);
    },
  );

  test('retryable capability failure can recover explicitly', () async {
    var attempts = 0;
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        walletPaymentCapabilitiesProvider.overrideWith((ref) async {
          attempts += 1;
          if (attempts == 1) {
            throw const AppFailureException(
              AppFailure(
                code: 'capabilities_timeout',
                kind: AppFailureKind.timeout,
                userMessage: 'Capabilities timed out.',
                retryable: true,
              ),
            );
          }
          return _capabilities();
        }),
      ],
    );
    final subscription = container.listen(
      swapViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    await expectLater(
      container.read(swapViewModelProvider.future),
      throwsA(isA<AppFailureException>()),
    );

    container.read(swapViewModelProvider.notifier).retry();
    final recovered = await container.read(swapViewModelProvider.future);

    expect(recovered.capabilities, _capabilities());
    expect(attempts, 2);
  });

  test('initial retry is inert for an already-loaded selection', () async {
    var attempts = 0;
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        walletPaymentCapabilitiesProvider.overrideWith((ref) async {
          attempts += 1;
          return _capabilities();
        }),
      ],
    );
    final transitions = <Object?>[];
    final subscription = container.listen(
      swapViewModelProvider,
      (_, next) => transitions.add(next),
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    await container.read(swapViewModelProvider.future);
    transitions.clear();

    container.read(swapViewModelProvider.notifier).retry();
    await Future<void>.delayed(Duration.zero);

    expect(transitions, isEmpty);
    expect(attempts, 1);
  });

  test('terminal capability failure cannot be retried', () async {
    var attempts = 0;
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        walletPaymentCapabilitiesProvider.overrideWith((ref) async {
          attempts += 1;
          throw const AppFailureException(
            AppFailure(
              code: 'capabilities_invalid',
              kind: AppFailureKind.configuration,
              userMessage: 'Capabilities are invalid.',
              retryable: false,
            ),
          );
        }),
      ],
    );
    final transitions = <Object?>[];
    final subscription = container.listen(
      swapViewModelProvider,
      (_, next) => transitions.add(next),
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    await expectLater(
      container.read(swapViewModelProvider.future),
      throwsA(isA<AppFailureException>()),
    );
    transitions.clear();

    container.read(swapViewModelProvider.notifier).retry();
    await Future<void>.delayed(Duration.zero);

    expect(transitions, isEmpty);
    expect(container.read(swapViewModelProvider), isA<AsyncError<SwapState>>());
    expect(attempts, 1);
  });
}

List<WalletPaymentCapability> _capabilities() => [
  WalletPaymentCapability.available(
    const PaymentRoute(asset: WalletAsset.bitcoin, rail: PaymentRail.onchain),
  ),
  WalletPaymentCapability.available(
    const PaymentRoute(asset: WalletAsset.bitcoin, rail: PaymentRail.lightning),
  ),
  const WalletPaymentCapability.unavailable(WalletPaymentTarget.usdtOnchain),
  const WalletPaymentCapability.unavailable(WalletPaymentTarget.usdtLightning),
];

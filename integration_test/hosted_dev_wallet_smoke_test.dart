import 'dart:convert';
import 'dart:io' show pid;

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _contractId = 'rgb:A6k89KtR-e3oXqRP-uH3jUrz-LU_sYL3-hMZ0k3O-6u8DXbE';
const _walletName = 'Hosted Dev smoke test';
const _smokeEnabled = bool.fromEnvironment('ASTER_DEV_WALLET_SMOKE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Hosted Dev wallet opens and uses the approved BUSDT contract', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final package = await PackageInfo.fromPlatform();
      final services = WalletServiceConfiguration.fromEnvironment();
      if (!kDebugMode ||
          !_smokeEnabled ||
          package.packageName != 'com.aster.devbridge.debug' ||
          !services.devBridgeEnabled ||
          services.backend != WalletBackend.rgbL1 ||
          services.environment != BlockchainEnvironment.signet ||
          services.usdtAsset?.contractId != _contractId) {
        throw StateError('Dedicated Hosted Dev smoke test build is required.');
      }

      final preferences = await SharedPreferences.getInstance();
      final container = createApplicationProviderContainer(preferences);
      final security = container.read(securityControllerProvider);
      final observer = _SecurityLifecycle(security);
      tester.binding.addObserver(observer);
      try {
        final profiles = await container.read(
          walletProfileStoreProvider.future,
        );
        final previous = _require(await profiles.read(), 'read registry');
        final fresh = previous.profiles.isEmpty;
        if (!fresh) {
          expect(previous.profiles, hasLength(1));
          expect(previous.activeProfile?.name, _walletName);
        }
        await security.initialize(hasWallet: previous.activeProfile != null);
        if (security.isLocked) {
          debugPrint('HOSTED_DEV_SMOKE_AUTH: Approve the device unlock.');
          expect(
            await security.unlock().timeout(const Duration(minutes: 1)),
            isTrue,
          );
        }
        expect(security.canAccessWallet, isTrue);

        final repository = await container.read(
          walletRepositoryProvider.future,
        );
        try {
          final opened = _require(await repository.bootstrap(), 'bootstrap');
          final registry = fresh
              ? _require(
                  await repository.createFromMnemonic(
                    mnemonic: _require(
                      await repository.generateMnemonic(),
                      'generate recovery phrase',
                    ),
                    name: _walletName,
                  ),
                  'provision wallet',
                )
              : opened;
          expect(registry.readyProfiles, hasLength(1));
          expect(registry.activeProfile?.name, _walletName);
          if (!fresh) {
            expect(registry.activeWalletId, previous.activeWalletId);
          }

          final status = _require(await repository.networkStatus(), 'network');
          expect(status.environment, BlockchainEnvironment.signet);
          _require(await repository.sync(), 'sync');
          final portfolio = _require(await repository.portfolio(), 'portfolio');
          final usdt = portfolio.usdt!;
          expect(usdt.asset.id.value, _contractId);
          expect(usdt.asset.precision, 6);
          expect(usdt.onchainSettled.units, 0);
          expect(portfolio.bitcoin.onchainSettled.units, 0);
          final fee = _require(await repository.estimateFeeRate(), 'fee quote');
          switch (fee.source) {
            case WalletFeeRateSource.devSignetPolicy:
              expect(fee.satsPerVbyte, 1);
            case WalletFeeRateSource.networkEstimate:
              expect(fee.satsPerVbyte, greaterThan(0));
            case WalletFeeRateSource.localRegtestPolicy:
            case WalletFeeRateSource.nativeRecovery:
              fail('Unexpected fee source for the Dev wallet.');
          }

          if (fresh) {
            final btc = _require(
              await repository.createReceiveRequest(
                WalletPaymentTarget.bitcoinOnchain,
              ),
              'Bitcoin address',
            );
            expect(btc.displayValue, startsWith('tb1'));
            final rgb = _require(
              await repository.createReceiveRequest(
                WalletPaymentTarget.usdtOnchain,
                amountUnits: 1250000,
              ),
              'BUSDT receive request',
            );
            final decoded = _require(
              await repository.previewPayment(
                WalletPaymentTarget.usdtOnchain,
                rgb.encodedRequest,
              ),
              'decode BUSDT receive request',
            );
            expect(decoded.route.asset.id.value, _contractId);
            expect(decoded.amount?.units, 1250000);
            expect(decoded.rgbRecipientType, RgbRecipientType.witness);
          }

          final receipt = {
            'mode': fresh ? 'create' : 'reopen',
            'pid': pid,
            'contractId': _contractId,
            'precision': usdt.asset.precision,
            'walletIdentitySha256': sha256
                .convert(utf8.encode(status.publicIdentity))
                .toString(),
            'btcSettled': portfolio.bitcoin.onchainSettled.units,
            'busdtSettled': usdt.onchainSettled.units,
            'feeSource': fee.source.name,
            'feeRate': fee.satsPerVbyte,
            'witnessReceiveChecked': fresh,
          };
          debugPrint('HOSTED_DEV_SMOKE ${jsonEncode(receipt)}');
        } finally {
          _require(await repository.dispose(), 'close wallet');
        }
      } finally {
        tester.binding.removeObserver(observer);
        container.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

final class _SecurityLifecycle extends WidgetsBindingObserver {
  _SecurityLifecycle(this.security);

  final SecurityController security;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    security.handleLifecycle(state);
  }
}

T _require<T>(AppResult<T> result, String step) => switch (result) {
  AppSuccess<T>(:final value) => value,
  AppFailureResult<T>(:final failure) => throw StateError(
    'Hosted Dev $step failed (${failure.code}).',
  ),
};

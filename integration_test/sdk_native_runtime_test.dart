import 'dart:convert';
import 'dart:io';

import 'package:aster/core/config/app_environment.dart';
import 'package:aster/core/config/signet_deployment.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

/// Checks the real SDK plugin packaged inside Aster without opening a wallet.
///
/// Run only under an isolated `com.aster.nativeqa.*.debug` application identity.
/// Runtime attestation does not open a wallet. Contract compatibility uses only
/// a fresh temporary wallet and a public fixture mnemonic, never existing app
/// storage, a network connection or funds. SDK unit tests cannot substitute for
/// these checks: the platform archive must match the Dart-side runtime pin.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Aster packages BFA.8 while production RGB_L1 stays gated', (
    tester,
  ) async {
    await _requireIsolatedIdentity();

    final runtime = await RgbLibWallet.getRuntimeInfo();
    expect(runtime.version, '0.3.0-beta.7-upstream-dev-bfa.8-bfa-flutter.1');
    expect(runtime.version, RgbLibRuntimeInfo.expectedVersion);
    expect(runtime.sourceRevision, RgbLibRuntimeInfo.expectedSourceRevision);
    expect(runtime.bridgeVersion, 6);
    expect(runtime.integrationTree, RgbLibRuntimeInfo.expectedIntegrationTree);
    expect(
      runtime.overlayPatchSha256,
      RgbLibRuntimeInfo.expectedOverlayPatchSha256,
    );
    expect(
      runtime.sourceLockSha256,
      RgbLibRuntimeInfo.expectedSourceLockSha256,
    );
    expect(
      runtime.sourceManifestSha256,
      RgbLibRuntimeInfo.expectedSourceManifestSha256,
    );
    expect(runtime.contractRegistration, isTrue);
    expect(runtime.durableOnchainRecovery, isTrue);
    expect(runtime.supportsExistingOnlyOpen, isTrue);
    expect(runtime.supportsDispatchedRgbRevocation, isTrue);
    expect(runtime.supportsDurableHostedDevBridge, isTrue);
    expect(WalletBackend.rgbL1.activationAllowed, isFalse);

    // Public artifact identity only. Never include wallet data in this receipt.
    debugPrint(
      'ASTER_SDK_RUNTIME_VERIFIED ${jsonEncode({'version': runtime.version, 'sourceRevision': runtime.sourceRevision, 'bridgeVersion': runtime.bridgeVersion, 'integrationTree': runtime.integrationTree, 'overlayPatchSha256': runtime.overlayPatchSha256, 'sourceLockSha256': runtime.sourceLockSha256, 'sourceManifestSha256': runtime.sourceManifestSha256, 'durableHostedBridge': runtime.supportsDurableHostedDevBridge, 'productionRgbL1Enabled': WalletBackend.rgbL1.activationAllowed})}',
    );
  });

  testWidgets('BFA.8 imports the approved Dev public contract offline', (
    tester,
  ) async {
    await _requireIsolatedIdentity();
    const contract = String.fromEnvironment('ASTER_QA_DEV_CONTRACT_BASE64');
    expect(contract, isNotEmpty);
    expect(
      sha256.convert(base64Decode(contract)).toString(),
      UtexoDevSignetPolicy.currentContractSha256,
    );

    final scratch = await Directory.systemTemp.createTemp('aster-bfa8-dev-');
    final wallet = RgbLibWallet(
      params: RgbLibWalletParams(
        network: 'utexo',
        allowUtexoDevSignet: true,
        storageDirPath: '${scratch.path}/wallet',
      ),
      keys: RgbLibKeys.mnemonic(
        'abandon abandon abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon about',
      ),
    );
    try {
      await wallet.init();
      final imported = await wallet.importContract(
        contractBase64: contract,
        expectedAssetId: UtexoDevSignetPolicy.currentAssetId,
      );
      expect(imported.assetId, UtexoDevSignetPolicy.currentAssetId);
      expect(imported.alreadyImported, isFalse);
      expect(imported.name, UtexoDevSignetPolicy.nativeAssetName);
      expect(imported.ticker, UtexoDevSignetPolicy.nativeAssetTicker);
      expect(imported.precision, UtexoDevSignetPolicy.assetPrecision);
      final metadata = await wallet.getAssetMetadata(imported.assetId);
      expect(metadata.assetSchema, RgbLibAssetSchema.bfa);
      expect(metadata.precision, UtexoDevSignetPolicy.assetPrecision);
      final repeated = await wallet.importContract(
        contractBase64: contract,
        expectedAssetId: UtexoDevSignetPolicy.currentAssetId,
      );
      expect(repeated.alreadyImported, isTrue);
      debugPrint(
        'ASTER_DEV_CONTRACT_OFFLINE_VERIFIED ${jsonEncode({'assetId': imported.assetId, 'contractSha256': UtexoDevSignetPolicy.currentContractSha256, 'name': imported.name, 'ticker': imported.ticker, 'precision': imported.precision, 'networkCalls': false, 'fundedOperations': false})}',
      );
    } finally {
      await wallet.destroy();
      await scratch.delete(recursive: true);
    }
  });
}

Future<void> _requireIsolatedIdentity() async {
  final package = await PackageInfo.fromPlatform();
  expect(kDebugMode, isTrue);
  expect(package.packageName, startsWith('com.aster.nativeqa.'));
  expect(package.packageName, endsWith('.debug'));
}

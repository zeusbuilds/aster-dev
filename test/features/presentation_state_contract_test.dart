import 'package:aster/core/core.dart';
import 'package:aster/features/home/presentation/models/models.dart';
import 'package:aster/features/settings/domain/models/models.dart';
import 'package:aster/features/settings/presentation/models/models.dart';
import 'package:aster/features/swap/presentation/models/models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nested presentation values compare by complete content', () {
    final rgbA = RgbAssetConfiguration(
      contractId: 'deployment-usdt',
      precision: 6,
    );
    final rgbB = RgbAssetConfiguration(
      contractId: 'deployment-usdt',
      precision: 6,
    );
    _expectEqualValue(rgbA, rgbB);
    expect(
      rgbA,
      isNot(RgbAssetConfiguration(contractId: 'deployment-usdt', precision: 8)),
    );

    _expectEqualValue(_services(), _services());
    expect(_services(), isNot(_services(lspBaseUrl: 'https://lsp.two.test')));

    final metadataA = AppBuildMetadata(version: '1.0.0', buildNumber: '7');
    final metadataB = AppBuildMetadata(version: '1.0.0', buildNumber: '7');
    _expectEqualValue(metadataA, metadataB);
    expect(
      metadataA,
      isNot(AppBuildMetadata(version: '1.0.0', buildNumber: '8')),
    );

    final snapshotA = _snapshot();
    final snapshotB = _snapshot();
    _expectEqualValue(snapshotA, snapshotB);
    expect(snapshotA, isNot(_snapshot(reverseCurrencies: true)));
  });

  test('published presentation states compare by complete content', () {
    _expectEqualValue(
      HomeState(portfolio: _portfolio(), refreshFailure: _failure),
      HomeState(portfolio: _portfolio(), refreshFailure: _failure),
    );
    _expectEqualValue(
      SettingsState(
        snapshot: _snapshot(),
        operation: SettingsOperation.currency,
        operationFailure: _failure,
      ),
      SettingsState(
        snapshot: _snapshot(),
        operation: SettingsOperation.currency,
        operationFailure: _failure,
      ),
    );
    _expectEqualValue(
      NetworkConfigurationState(
        configuration: _services(),
        healthFailure: _failure,
      ),
      NetworkConfigurationState(
        configuration: _services(),
        healthFailure: _failure,
      ),
    );
    _expectEqualValue(
      SettingsAppState(
        availableLinks: const {
          SettingsExternalLink.contactSupport,
          SettingsExternalLink.privacyPolicy,
        },
        metadata: AppBuildMetadata(version: '1.0.0', buildNumber: '7'),
        operationFailure: _failure,
      ),
      SettingsAppState(
        availableLinks: const {
          SettingsExternalLink.privacyPolicy,
          SettingsExternalLink.contactSupport,
        },
        metadata: AppBuildMetadata(version: '1.0.0', buildNumber: '7'),
        operationFailure: _failure,
      ),
    );
    _expectEqualValue(
      SwapState(
        capabilities: _capabilities(),
        from: WalletPaymentTarget.bitcoinOnchain,
        to: WalletPaymentTarget.bitcoinLightning,
      ),
      SwapState(
        capabilities: _capabilities(),
        from: WalletPaymentTarget.bitcoinOnchain,
        to: WalletPaymentTarget.bitcoinLightning,
      ),
    );
  });

  test('every state field participates in inequality', () {
    expect(
      HomeState(portfolio: _portfolio()),
      isNot(HomeState(portfolio: _portfolio(), refreshing: true)),
    );
    expect(
      SettingsState(snapshot: _snapshot()),
      isNot(
        SettingsState(
          snapshot: _snapshot(),
          operation: SettingsOperation.region,
        ),
      ),
    );
    expect(
      NetworkConfigurationState(configuration: _services()),
      isNot(
        NetworkConfigurationState(configuration: _services(), refreshing: true),
      ),
    );
    expect(
      SettingsAppState(
        availableLinks: const {SettingsExternalLink.contactSupport},
      ),
      isNot(
        SettingsAppState(
          availableLinks: const {SettingsExternalLink.contactSupport},
          metadataLoading: true,
        ),
      ),
    );
    expect(
      SwapState(
        capabilities: _capabilities(),
        from: WalletPaymentTarget.bitcoinOnchain,
        to: WalletPaymentTarget.bitcoinLightning,
      ),
      isNot(
        SwapState(
          capabilities: _capabilities(),
          from: WalletPaymentTarget.bitcoinLightning,
          to: WalletPaymentTarget.bitcoinOnchain,
        ),
      ),
    );
  });
}

const _failure = AppFailure(
  code: 'presentation_unavailable',
  kind: AppFailureKind.unavailable,
  userMessage: 'Presentation data is unavailable.',
  retryable: true,
);

void _expectEqualValue(Object left, Object right) {
  expect(left, right);
  expect(left.hashCode, right.hashCode);
}

WalletServiceConfiguration _services({
  String lspBaseUrl = 'https://lsp.one.test',
}) {
  return WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
    indexerUrl: 'tcp://127.0.0.1:51001',
    rgbTransportProxy: 'http://127.0.0.1:3100',
    lspBaseUrl: lspBaseUrl,
    vssUrl: 'http://127.0.0.1:3101',
    usdtAsset: RgbAssetConfiguration(
      contractId: 'deployment-usdt',
      precision: 6,
    ),
  );
}

SettingsSnapshot _snapshot({bool reverseCurrencies = false}) {
  final currencies = <FiatCurrency>[
    FiatCurrency(
      name: 'US Dollar',
      symbol: r'$',
      code: 'USD',
      countryCode: 'US',
    ),
    FiatCurrency(name: 'Euro', symbol: 'EUR', code: 'EUR', countryCode: 'DE'),
  ];
  return SettingsSnapshot(
    preferences: AppPreferences.defaults,
    currencies: reverseCurrencies ? currencies.reversed.toList() : currencies,
    regions: [
      Region(name: 'United States', code: 'US'),
      Region(name: 'Germany', code: 'DE'),
    ],
  );
}

WalletPortfolio _portfolio() {
  final assetId = WalletAsset.bitcoin.id;
  return WalletPortfolio(
    bitcoin: WalletBalance(
      asset: WalletAsset.bitcoin,
      onchainSettled: WalletAmount.onchain(assetId: assetId, units: 1200),
      onchainFuture: WalletAmount.onchain(assetId: assetId, units: 1200),
      onchainSpendable: WalletAmount.onchain(assetId: assetId, units: 1000),
      onchainLocked: WalletAmount.onchain(assetId: assetId, units: 200),
      lightningOwned: WalletAmount.lightning(assetId: assetId, units: 3000),
      lightningSpendable: WalletAmount.lightning(assetId: assetId, units: 2000),
      lightningReceivable: WalletAmount.lightning(
        assetId: assetId,
        units: 4000,
      ),
    ),
  );
}

List<WalletPaymentCapability> _capabilities() => [
  WalletPaymentCapability.available(
    const PaymentRoute(asset: WalletAsset.bitcoin, rail: PaymentRail.onchain),
  ),
  WalletPaymentCapability.available(
    const PaymentRoute(asset: WalletAsset.bitcoin, rail: PaymentRail.lightning),
  ),
];

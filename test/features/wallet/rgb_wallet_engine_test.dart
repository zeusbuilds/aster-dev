import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

final class MockUtexoWallet extends Mock implements UtexoWallet {}

final class MockRgbSdkFlutter extends Mock implements RgbSdkFlutter {}

const _nodePublicKey =
    '020000000000000000000000000000000000000000000000000000000000000000';

const _nodeInfo = WalletNodeInfo(
  pubkey: _nodePublicKey,
  numChannels: 2,
  numUsableChannels: 1,
  localBalanceSat: 0,
  numPeers: 1,
);

void main() {
  const services = WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
  );

  setUpAll(() {
    registerFallbackValue(UtexoUnlockConfig());
    registerFallbackValue(UtexoWalletConfig(storageDirPath: '/wallet'));
  });

  test('forwards validated local VSS transport policy to the SDK', () {
    final sdk = MockRgbSdkFlutter();
    final wallet = MockUtexoWallet();
    when(() => sdk.wallet(config: any(named: 'config'))).thenReturn(wallet);
    const localServices = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      vssUrl: 'http://127.0.0.1:3200',
    );
    final factory = RgbWalletEngineFactory(sdk);

    factory.create(
      const WalletEngineConfiguration(
        storageDirectory: '/wallet',
        services: localServices,
      ),
    );

    final config =
        verify(
              () => sdk.wallet(config: captureAny(named: 'config')),
            ).captured.single
            as UtexoWalletConfig;
    expect(config.vssUrl, localServices.vssUrl);
    expect(config.vssAllowHttp, isTrue);
  });

  test('initializes and unlocks through the stable wallet facade', () async {
    final wallet = MockUtexoWallet();
    final unlock = UtexoUnlockConfig(
      indexerUrl: 'http://127.0.0.1:50002',
      proxyEndpoint: 'http://127.0.0.1:3001',
    );
    when(
      () => wallet.init(
        password: any(named: 'password'),
        mnemonic: any(named: 'mnemonic'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => wallet.unlock(
        password: any(named: 'password'),
        config: any(named: 'config'),
      ),
    ).thenAnswer((_) async {});
    final engine = RgbWalletEngine(wallet, services, unlock);

    await engine.initialize(
      databasePassword: 'database-password',
      mnemonic: 'mnemonic words',
    );

    verify(
      () => wallet.init(
        password: 'database-password',
        mnemonic: 'mnemonic words',
      ),
    ).called(1);
    verify(
      () => wallet.unlock(password: 'database-password', config: unlock),
    ).called(1);
  });

  test('returns validated native network status', () async {
    final wallet = MockUtexoWallet();
    when(() => wallet.getNetworkInfo()).thenAnswer(
      (_) async => const WalletNetworkInfo(network: 'regtest', height: 42),
    );
    when(() => wallet.getNodeInfo()).thenAnswer((_) async => _nodeInfo);
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    final status = await engine.getNetworkStatus();

    expect(status.environment, BlockchainEnvironment.regtest);
    expect(status.blockHeight, 42);
    expect(status.usableChannelCount, 1);
  });

  test(
    'rejects a native network that differs from app configuration',
    () async {
      final wallet = MockUtexoWallet();
      when(() => wallet.getNetworkInfo()).thenAnswer(
        (_) async => const WalletNetworkInfo(network: 'mainnet', height: 42),
      );
      when(() => wallet.getNodeInfo()).thenAnswer((_) async => _nodeInfo);
      final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

      await expectLater(
        engine.getNetworkStatus(),
        throwsA(isA<NativeProtocolException>()),
      );
      verifyNever(() => wallet.getNodeInfo());
    },
  );

  test('rejects an unknown native network before reading node state', () async {
    final wallet = MockUtexoWallet();
    when(() => wallet.getNetworkInfo()).thenAnswer(
      (_) async => const WalletNetworkInfo(network: 'unknown', height: 42),
    );
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    await expectLater(
      engine.getNetworkStatus(),
      throwsA(isA<NativeProtocolException>()),
    );
    verifyNever(() => wallet.getNodeInfo());
  });

  test(
    'rejects padded native network values before reading node state',
    () async {
      final wallet = MockUtexoWallet();
      when(() => wallet.getNetworkInfo()).thenAnswer(
        (_) async => const WalletNetworkInfo(network: ' regtest', height: 42),
      );
      final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

      await expectLater(
        engine.getNetworkStatus(),
        throwsA(isA<NativeProtocolException>()),
      );
      verifyNever(() => wallet.getNodeInfo());
    },
  );

  test('rejects malformed native node counters and keys', () async {
    final wallet = MockUtexoWallet();
    when(() => wallet.getNetworkInfo()).thenAnswer(
      (_) async => const WalletNetworkInfo(network: 'regtest', height: 42),
    );
    when(() => wallet.getNodeInfo()).thenAnswer(
      (_) async => const WalletNodeInfo(
        pubkey: 'not-a-node-key',
        numChannels: 1,
        numUsableChannels: 2,
        localBalanceSat: 0,
        numPeers: 0,
      ),
    );
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    await expectLater(
      engine.getNetworkStatus(),
      throwsA(isA<NativeProtocolException>()),
    );
  });

  test('exports both account xpubs only when values are complete', () async {
    final wallet = MockUtexoWallet();
    when(() => wallet.getNodeInfo()).thenAnswer(
      (_) async => const WalletNodeInfo(
        pubkey: _nodePublicKey,
        numChannels: 0,
        numUsableChannels: 0,
        localBalanceSat: 0,
        numPeers: 0,
        accountXpubVanilla: 'tpub-bitcoin',
        accountXpubColored: 'tpub-rgb',
      ),
    );
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    final keys = await engine.getPublicKeys();

    expect(keys.bitcoin, 'tpub-bitcoin');
    expect(keys.rgb, 'tpub-rgb');
  });

  test('rejects missing or whitespace-corrupted account xpubs', () async {
    final wallet = MockUtexoWallet();
    when(() => wallet.getNodeInfo()).thenAnswer(
      (_) async => const WalletNodeInfo(
        pubkey: _nodePublicKey,
        numChannels: 0,
        numUsableChannels: 0,
        localBalanceSat: 0,
        numPeers: 0,
        accountXpubVanilla: ' tpub-bitcoin',
      ),
    );
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    await expectLater(
      engine.getPublicKeys(),
      throwsA(isA<NativeProtocolException>()),
    );
  });

  test('rejects internal xpub whitespace as malformed native data', () async {
    final wallet = MockUtexoWallet();
    when(() => wallet.getNodeInfo()).thenAnswer(
      (_) async => const WalletNodeInfo(
        pubkey: _nodePublicKey,
        numChannels: 0,
        numUsableChannels: 0,
        localBalanceSat: 0,
        numPeers: 0,
        accountXpubVanilla: 'tpub btc',
        accountXpubColored: 'tpub-rgb',
      ),
    );
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    await expectLater(
      engine.getPublicKeys(),
      throwsA(isA<NativeProtocolException>()),
    );
  });

  test('accepts only receive addresses for the configured network', () async {
    final wallet = MockUtexoWallet();
    when(() => wallet.getAddress()).thenAnswer((_) async => 'bcrt1qexample');
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    expect(await engine.getBitcoinAddress(), 'bcrt1qexample');

    when(() => wallet.getAddress()).thenAnswer((_) async => 'bc1qmainnet');
    await expectLater(
      engine.getBitcoinAddress(),
      throwsA(isA<NativeProtocolException>()),
    );
  });

  test(
    'maps Bitcoin balance dimensions without ticker or double math',
    () async {
      final wallet = MockUtexoWallet();
      when(() => wallet.getBtcBalance()).thenAnswer(
        (_) async => const CoreBtcBalance(
          vanilla: CoreBalance(settled: 100, future: 130, spendable: 80),
          colored: CoreBalance(settled: 20, future: 25, spendable: 0),
        ),
      );
      when(() => wallet.getNodeInfo()).thenAnswer(
        (_) async => const WalletNodeInfo(
          pubkey: _nodePublicKey,
          numChannels: 2,
          numUsableChannels: 1,
          localBalanceSat: 4,
          numPeers: 1,
        ),
      );
      when(() => wallet.listChannels()).thenAnswer(
        (_) async => const [
          LightningChannel(
            channelId: 'one',
            peerPubkey: 'peer-one',
            capacitySat: 10,
            ready: true,
            isPublic: false,
            isUsable: true,
            localBalanceMsat: 1500,
            outboundBalanceMsat: 1200,
            inboundBalanceMsat: 300,
          ),
          LightningChannel(
            channelId: 'two',
            peerPubkey: 'peer-two',
            capacitySat: 10,
            ready: true,
            isPublic: false,
            isUsable: false,
            localBalanceMsat: 2500,
            outboundBalanceMsat: 2000,
            inboundBalanceMsat: 1000,
          ),
        ],
      );
      final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

      final balance = await engine.getBalance(WalletAsset.bitcoin);

      expect(balance.onchainSettled.units, 120);
      expect(balance.onchainFuture.units, 155);
      expect(balance.onchainPendingDeltaUnits, 35);
      expect(balance.onchainSpendable.units, 80);
      expect(balance.onchainLocked.units, 40);
      expect(balance.lightningOwned.units, 4000);
      expect(balance.lightningSpendable.units, 1200);
      expect(balance.lightningReceivable.units, 300);
      expect(balance.totalBitcoinMillisatoshis, 124000);
      expect(balance.availableBitcoinMillisatoshis, 81200);
      expect(balance.totalAssetUnits, 124);
      expect(balance.availableAssetUnits, 81);
    },
  );

  test('maps RGB asset channels by immutable contract ID', () async {
    final wallet = MockUtexoWallet();
    const assetId = 'rgb:usdt-contract';
    when(() => wallet.getAssetBalance(assetId)).thenAnswer(
      (_) async => const CoreAssetBalance(
        settled: 1000,
        future: 1100,
        spendable: 700,
        offchainOutbound: 80,
        offchainInbound: 90,
      ),
    );
    when(() => wallet.listChannels()).thenAnswer(
      (_) async => const [
        LightningChannel(
          channelId: 'rgb',
          peerPubkey: 'peer',
          capacitySat: 10,
          ready: true,
          isPublic: false,
          assetId: assetId,
          assetLocalAmount: 120,
        ),
        LightningChannel(
          channelId: 'other',
          peerPubkey: 'peer',
          capacitySat: 10,
          ready: true,
          isPublic: false,
          assetId: 'other-contract',
          assetLocalAmount: 999,
        ),
      ],
    );
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    final balance = await engine.getBalance(
      WalletAsset.rgbUsdt(assetId: assetId, precision: 6),
    );

    expect(balance.onchainFuture.units, 1100);
    expect(balance.onchainPendingDeltaUnits, 100);
    expect(balance.onchainLocked.units, 300);
    expect(balance.lightningOwned.units, 120);
    expect(balance.lightningSpendable.units, 80);
    expect(balance.lightningReceivable.units, 90);
  });

  test('preserves a negative pending delta for outgoing Bitcoin', () async {
    final wallet = MockUtexoWallet();
    when(() => wallet.getBtcBalance()).thenAnswer(
      (_) async => const CoreBtcBalance(
        vanilla: CoreBalance(settled: 100, future: 75, spendable: 70),
        colored: CoreBalance(settled: 20, future: 15, spendable: 0),
      ),
    );
    when(() => wallet.getNodeInfo()).thenAnswer(
      (_) async => const WalletNodeInfo(
        pubkey: _nodePublicKey,
        numChannels: 0,
        numUsableChannels: 0,
        localBalanceSat: 0,
        numPeers: 0,
      ),
    );
    when(() => wallet.listChannels()).thenAnswer((_) async => const []);
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    final balance = await engine.getBalance(WalletAsset.bitcoin);

    expect(balance.onchainSettled.units, 120);
    expect(balance.onchainFuture.units, 90);
    expect(balance.onchainPendingDeltaUnits, -30);
  });

  test('rejects negative native monetary values instead of clamping', () async {
    final wallet = MockUtexoWallet();
    when(() => wallet.getBtcBalance()).thenAnswer(
      (_) async => const CoreBtcBalance(
        vanilla: CoreBalance(settled: 100, future: 100, spendable: 80),
        colored: CoreBalance(settled: 0, future: 0, spendable: 0),
      ),
    );
    when(() => wallet.listChannels()).thenAnswer(
      (_) async => const [
        LightningChannel(
          channelId: 'invalid',
          peerPubkey: 'peer',
          capacitySat: 1,
          ready: true,
          isPublic: false,
          isUsable: true,
          outboundBalanceMsat: -1,
          inboundBalanceMsat: 0,
        ),
      ],
    );
    when(() => wallet.getNodeInfo()).thenAnswer((_) async => _nodeInfo);
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    await expectLater(
      engine.getBalance(WalletAsset.bitcoin),
      throwsA(isA<NativeProtocolException>()),
    );
  });

  test('rejects missing liquidity on a channel reported as usable', () async {
    final wallet = MockUtexoWallet();
    when(() => wallet.getBtcBalance()).thenAnswer(
      (_) async => const CoreBtcBalance(
        vanilla: CoreBalance(settled: 100, future: 100, spendable: 80),
        colored: CoreBalance(settled: 0, future: 0, spendable: 0),
      ),
    );
    when(() => wallet.getNodeInfo()).thenAnswer((_) async => _nodeInfo);
    when(() => wallet.listChannels()).thenAnswer(
      (_) async => const [
        LightningChannel(
          channelId: 'invalid',
          peerPubkey: 'peer',
          capacitySat: 1,
          ready: true,
          isPublic: false,
          isUsable: true,
        ),
      ],
    );
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    await expectLater(
      engine.getBalance(WalletAsset.bitcoin),
      throwsA(isA<NativeProtocolException>()),
    );
  });

  test('rejects native balance aggregation overflow', () async {
    final wallet = MockUtexoWallet();
    when(() => wallet.getBtcBalance()).thenAnswer(
      (_) async => const CoreBtcBalance(
        vanilla: CoreBalance(
          settled: WalletAmount.maxNativeUnits,
          future: WalletAmount.maxNativeUnits,
          spendable: WalletAmount.maxNativeUnits,
        ),
        colored: CoreBalance(settled: 1, future: 1, spendable: 0),
      ),
    );
    when(() => wallet.getNodeInfo()).thenAnswer((_) async => _nodeInfo);
    when(() => wallet.listChannels()).thenAnswer((_) async => const []);
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    await expectLater(
      engine.getBalance(WalletAsset.bitcoin),
      throwsA(isA<NativeProtocolException>()),
    );
  });
}

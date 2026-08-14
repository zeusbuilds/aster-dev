import 'dart:typed_data';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:dart_bech32/dart_bech32.dart' as bech32_codec;
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
    registerFallbackValue(const RgbInvoiceRequest());
    registerFallbackValue(
      const RgbSendRequest(invoice: 'rgb:fallback', amount: 1),
    );
    registerFallbackValue(const LightningAsset(assetId: 'fallback', amount: 1));
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
    final factory = RgbWalletEngineFactory.withSdk(sdk);

    factory.create(
      const WalletEngineConfiguration(
        storageDirectory: '/wallet',
        services: localServices,
      ),
    );

    final config =
        verify(() => sdk.wallet(config: captureAny(named: 'config')))
                .captured
                .single
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
    verify(() => wallet.unlock(password: 'database-password', config: unlock))
        .called(1);
  });

  test(
    'rounds native fee estimates up and records UTC observation time',
    () async {
      final observedAt = DateTime.utc(2026, 8, 11, 10);
      final wallet = MockUtexoWallet();
      when(() => wallet.estimateFeeRate(6))
          .thenAnswer((_) async => const FeeEstimationResponse(feeRate: 1.25));
      final engine = RgbWalletEngine(
        wallet,
        services,
        UtexoUnlockConfig(),
        clock: () => observedAt,
      );

      final estimate = await engine.estimateFeeRate(6);

      expect(estimate.targetBlocks, 6);
      expect(estimate.satsPerVbyte, 2);
      expect(estimate.observedAt, observedAt);
    },
  );

  test('rejects invalid fee targets and malformed native estimates', () async {
    final invalidTargetWallet = MockUtexoWallet();
    final invalidTargetEngine = RgbWalletEngine(
      invalidTargetWallet,
      services,
      UtexoUnlockConfig(),
    );

    await expectLater(
      invalidTargetEngine.estimateFeeRate(0),
      throwsA(isA<WalletValidationException>()),
    );
    verifyNever(() => invalidTargetWallet.estimateFeeRate(any()));

    for (final value in <double>[
      0,
      double.nan,
      double.infinity,
      WalletFeeRateEstimate.maximumSatsPerVbyte + 0.1,
    ]) {
      final wallet = MockUtexoWallet();
      when(() => wallet.estimateFeeRate(6))
          .thenAnswer((_) async => FeeEstimationResponse(feeRate: value));
      final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

      await expectLater(
        engine.estimateFeeRate(6),
        throwsA(isA<NativeProtocolException>()),
      );
    }
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
    final address = _regtestAddress();
    when(() => wallet.getAddress()).thenAnswer((_) async => address);
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    expect(await engine.getBitcoinAddress(), address);

    when(() => wallet.getAddress())
        .thenAnswer((_) async => '1BoatSLRHtKNngkdXEeobR76b53LETtpyT');
    await expectLater(
      engine.getBitcoinAddress(),
      throwsA(isA<NativeProtocolException>()),
    );

    when(
      () => wallet.getAddress(),
    ).thenAnswer((_) async => '${address.substring(0, address.length - 1)}x');
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

  test('creates Bitcoin URI requests and sends in integer sats', () async {
    final wallet = MockUtexoWallet();
    final address = _regtestAddress();
    when(() => wallet.getAddress()).thenAnswer((_) async => address);
    when(() => wallet.sendBtc(amount: 123456789, address: address, feeRate: 3))
        .thenAnswer((_) async => 'bitcoin-txid');
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );
    final amount = WalletAmount.onchain(
      assetId: WalletAsset.bitcoin.id,
      units: 123456789,
    );

    final receive = await engine.createReceiveRequest(route, amount: amount);
    final sent = await engine.sendPayment(
      WalletSendCommand(
        route: route,
        destination: address,
        amount: amount,
        feeRate: _feeRate(3),
      ),
    );

    expect(receive.encodedRequest, 'bitcoin:$address?amount=1.23456789');
    expect(receive.displayValue, address);
    expect(sent.referenceId, 'bitcoin-txid');
    expect(sent.status, WalletPaymentStatus.pending);
  });

  test('rejects invalid Bitcoin destinations before native mutation', () async {
    final wallet = MockUtexoWallet();
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );

    await expectLater(
      engine.sendPayment(
        WalletSendCommand(
          route: route,
          destination: 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfU',
          amount: WalletAmount.onchain(
            assetId: WalletAsset.bitcoin.id,
            units: 1,
          ),
          feeRate: _feeRate(1),
        ),
      ),
      throwsA(isA<WalletValidationException>()),
    );
    verifyNever(
      () => wallet.sendBtc(
        amount: any(named: 'amount'),
        address: any(named: 'address'),
        feeRate: any(named: 'feeRate'),
      ),
    );
  });

  test('rejects invisible Unicode in a native receive request', () async {
    final wallet = MockUtexoWallet();
    when(
      () =>
          wallet.createLightningInvoice(amountSats: null, expirySeconds: 3600),
    ).thenAnswer(
      (_) async =>
          const LightningReceiveRequest(lnInvoice: 'lnbcrt1invoice\u200b'),
    );
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );

    await expectLater(
      engine.createReceiveRequest(route),
      throwsA(
        isA<NativeProtocolException>().having(
          (error) => error.field,
          'field',
          'LightningReceiveRequest.lnInvoice',
        ),
      ),
    );
    verifyNever(() => wallet.decodeLnInvoice(any()));
  });

  test('creates, verifies, and pays Bitcoin Lightning invoices', () async {
    final createdAt = DateTime.utc(2026, 8, 11, 10);
    final timestamp = createdAt.millisecondsSinceEpoch ~/ 1000;
    final wallet = MockUtexoWallet();
    when(
      () => wallet.createLightningInvoice(amountSats: 2, expirySeconds: 3600),
    ).thenAnswer(
      (_) async => const LightningReceiveRequest(lnInvoice: 'lnbcrt1bitcoin'),
    );
    when(() => wallet.decodeLnInvoice('lnbcrt1bitcoin')).thenAnswer(
      (_) async => DecodedLightningInvoice(
        amtMsat: 2000,
        expirySec: 3600,
        timestamp: timestamp,
        paymentHash: 'bitcoin-payment-hash',
        paymentSecret: 'not-retained',
        network: 'regtest',
      ),
    );
    when(
      () => wallet.payLightningInvoice(
        lnInvoice: 'lnbcrt1bitcoin',
        amount: null,
        assetId: null,
        assetAmount: null,
      ),
    ).thenAnswer(
      (_) async => const LightningSendRequest(
        txid: 'bitcoin-payment-hash',
        status: RlnPaymentStatuses.succeeded,
      ),
    );
    final engine = RgbWalletEngine(
      wallet,
      services,
      UtexoUnlockConfig(),
      clock: () => createdAt,
    );
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    final amount = WalletAmount.lightning(
      assetId: WalletAsset.bitcoin.id,
      units: 2000,
    );

    final receive = await engine.createReceiveRequest(route, amount: amount);
    final sent = await engine.sendPayment(
      WalletSendCommand(
        route: route,
        destination: receive.encodedRequest,
        amount: amount,
      ),
    );

    expect(receive.amount, amount);
    expect(receive.expiresAt, createdAt.add(const Duration(hours: 1)));
    expect(receive.referenceId, 'bitcoin-payment-hash');
    expect(sent.status, WalletPaymentStatus.succeeded);
  });

  test(
    'passes sats only for an amountless Bitcoin Lightning invoice',
    () async {
      final createdAt = DateTime.utc(2026, 8, 11, 10);
      final wallet = MockUtexoWallet();
      when(() => wallet.decodeLnInvoice('lnbcrt1amountless')).thenAnswer(
        (_) async => DecodedLightningInvoice(
          expirySec: 3600,
          timestamp: createdAt.millisecondsSinceEpoch ~/ 1000,
          paymentHash: 'amountless-payment-hash',
          paymentSecret: 'not-retained',
          network: 'regtest',
        ),
      );
      when(
        () => wallet.payLightningInvoice(
          lnInvoice: 'lnbcrt1amountless',
          amount: 21,
          assetId: null,
          assetAmount: null,
        ),
      ).thenAnswer(
        (_) async =>
            const LightningSendRequest(txid: 'amountless-payment-hash'),
      );
      final engine = RgbWalletEngine(
        wallet,
        services,
        UtexoUnlockConfig(),
        clock: () => createdAt,
      );
      const route = PaymentRoute(
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.lightning,
      );

      final result = await engine.sendPayment(
        WalletSendCommand(
          route: route,
          destination: 'lnbcrt1amountless',
          amount: WalletAmount.lightning(
            assetId: WalletAsset.bitcoin.id,
            units: 21000,
          ),
        ),
      );

      expect(result.status, WalletPaymentStatus.pending);
    },
  );

  test('creates, verifies, and sends configured RGB on-chain USDT', () async {
    const assetId = 'rgb:configured-usdt';
    const configuredServices = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      usdtAsset: RgbAssetConfiguration(contractId: assetId, precision: 6),
    );
    final asset = WalletAsset.rgbUsdt(assetId: assetId, precision: 6);
    final route = PaymentRoute(asset: asset, rail: PaymentRail.onchain);
    final amount = WalletAmount.onchain(assetId: asset.id, units: 1250000);
    final wallet = MockUtexoWallet();
    when(() => wallet.onchainReceive(any())).thenAnswer(
      (_) async => const OnchainReceiveResponse(
        invoice: 'rgb:invoice',
        recipientId: 'rgb-recipient',
        expirationTimestamp: 1786446000,
        batchTransferIdx: 7,
      ),
    );
    when(() => wallet.decodeRgbInvoice('rgb:invoice')).thenAnswer(
      (_) async => CoreInvoiceData(
        invoice: 'rgb:invoice',
        recipientId: 'rgb-recipient',
        assetId: assetId,
        network: 'regtest',
        assignment: const Assignment(type: 'Fungible', amount: 1250000),
        expirationTimestamp: 1786446000,
        transportEndpoints: const <String>[],
      ),
    );
    when(() => wallet.onchainSend(any())).thenAnswer(
      (_) async => const OnchainSendResponse(
        txid: 'rgb-bitcoin-txid',
        batchTransferIdx: 8,
      ),
    );
    final engine = RgbWalletEngine(
      wallet,
      configuredServices,
      UtexoUnlockConfig(),
      clock: () => DateTime.utc(2026, 8, 11, 10),
    );

    final receive = await engine.createReceiveRequest(route, amount: amount);
    final sent = await engine.sendPayment(
      WalletSendCommand(
        route: route,
        destination: receive.encodedRequest,
        amount: amount,
        feeRate: _feeRate(4),
      ),
    );

    final receiveRequest =
        verify(() => wallet.onchainReceive(captureAny())).captured.single
            as RgbInvoiceRequest;
    final sendRequest =
        verify(() => wallet.onchainSend(captureAny())).captured.single
            as RgbSendRequest;
    expect(receiveRequest.assetId, assetId);
    expect(receiveRequest.amount, 1250000);
    expect(receiveRequest.durationSeconds, 3600);
    expect(receive.batchTransferIndex, 7);
    expect(sendRequest.assetId, assetId);
    expect(sendRequest.amount, 1250000);
    expect(sendRequest.feeRate, 4);
    expect(sent.referenceId, 'rgb-bitcoin-txid');
    expect(sent.batchTransferIndex, 8);
  });

  test(
    'requires amount and binds configured asset for RGB Lightning',
    () async {
      const assetId = 'rgb:configured-usdt';
      const configuredServices = WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        usdtAsset: RgbAssetConfiguration(contractId: assetId, precision: 6),
      );
      final asset = WalletAsset.rgbUsdt(assetId: assetId, precision: 6);
      final route = PaymentRoute(asset: asset, rail: PaymentRail.lightning);
      final amount = WalletAmount.lightning(assetId: asset.id, units: 2500000);
      final createdAt = DateTime.utc(2026, 8, 11, 10);
      final wallet = MockUtexoWallet();
      when(
        () => wallet.createLightningInvoice(
          asset: any(named: 'asset'),
          expirySeconds: 3600,
        ),
      ).thenAnswer(
        (_) async => const LightningReceiveRequest(lnInvoice: 'lnbcrt1rgb'),
      );
      when(() => wallet.decodeLnInvoice('lnbcrt1rgb')).thenAnswer(
        (_) async => DecodedLightningInvoice(
          expirySec: 3600,
          timestamp: createdAt.millisecondsSinceEpoch ~/ 1000,
          assetId: assetId,
          assetAmount: 2500000,
          paymentHash: 'rgb-payment-hash',
          paymentSecret: 'not-retained',
          network: 'regtest',
        ),
      );
      when(
        () => wallet.payLightningInvoice(
          lnInvoice: 'lnbcrt1rgb',
          amount: null,
          assetId: assetId,
          assetAmount: 2500000,
        ),
      ).thenAnswer(
        (_) async => const LightningSendRequest(
          txid: 'rgb-payment-hash',
          status: RlnPaymentStatuses.pending,
        ),
      );
      final engine = RgbWalletEngine(
        wallet,
        configuredServices,
        UtexoUnlockConfig(),
        clock: () => createdAt,
      );

      await expectLater(
        engine.createReceiveRequest(route),
        throwsA(isA<WalletValidationException>()),
      );
      final receive = await engine.createReceiveRequest(route, amount: amount);
      final sent = await engine.sendPayment(
        WalletSendCommand(
          route: route,
          destination: receive.encodedRequest,
          amount: amount,
        ),
      );

      final nativeAsset =
          verify(
                () => wallet.createLightningInvoice(
                  asset: captureAny(named: 'asset'),
                  expirySeconds: 3600,
                ),
              ).captured.single
              as LightningAsset;
      expect(nativeAsset.assetId, assetId);
      expect(nativeAsset.amount, 2500000);
      expect(sent.referenceId, 'rgb-payment-hash');
    },
  );

  test(
    'rejects mismatched, expired, and unconfigured payment requests',
    () async {
      final createdAt = DateTime.utc(2026, 8, 11, 10);
      final wallet = MockUtexoWallet();
      when(() => wallet.decodeLnInvoice('lnbcrt1expired')).thenAnswer(
        (_) async => DecodedLightningInvoice(
          amtMsat: 1000,
          expirySec: 1,
          timestamp: createdAt.millisecondsSinceEpoch ~/ 1000,
          paymentHash: 'expired-payment-hash',
          paymentSecret: 'not-retained',
          network: 'regtest',
        ),
      );
      when(() => wallet.decodeLnInvoice('lntb1wrongnetwork')).thenAnswer(
        (_) async => DecodedLightningInvoice(
          amtMsat: 1000,
          expirySec: 3600,
          timestamp: createdAt.millisecondsSinceEpoch ~/ 1000,
          paymentHash: 'wrong-network-hash',
          paymentSecret: 'not-retained',
          network: 'mainnet',
        ),
      );
      final engine = RgbWalletEngine(
        wallet,
        services,
        UtexoUnlockConfig(),
        clock: () => createdAt.add(const Duration(seconds: 2)),
      );
      const bitcoinRoute = PaymentRoute(
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.lightning,
      );
      final amount = WalletAmount.lightning(
        assetId: WalletAsset.bitcoin.id,
        units: 1000,
      );

      await expectLater(
        engine.sendPayment(
          WalletSendCommand(
            route: bitcoinRoute,
            destination: 'lnbcrt1expired',
            amount: amount,
          ),
        ),
        throwsA(isA<WalletValidationException>()),
      );
      await expectLater(
        engine.decodeInvoice(bitcoinRoute, 'lntb1wrongnetwork'),
        throwsA(isA<WalletValidationException>()),
      );
      final unconfiguredUsdt = WalletAsset.rgbUsdt(
        assetId: 'rgb:not-configured',
        precision: 6,
      );
      await expectLater(
        engine.decodeInvoice(
          PaymentRoute(asset: unconfiguredUsdt, rail: PaymentRail.onchain),
          'rgb:invoice',
        ),
        throwsA(isA<AppConfigurationException>()),
      );
      verifyNever(
        () => wallet.payLightningInvoice(
          lnInvoice: any(named: 'lnInvoice'),
          amount: any(named: 'amount'),
          assetId: any(named: 'assetId'),
          assetAmount: any(named: 'assetAmount'),
        ),
      );
    },
  );

  test('rejects deceptive Unicode in native payment identifiers', () async {
    final createdAt = DateTime.utc(2026, 8, 11, 10);
    final wallet = MockUtexoWallet();
    when(() => wallet.decodeLnInvoice('lnbcrt1malformed')).thenAnswer(
      (_) async => DecodedLightningInvoice(
        amtMsat: 1000,
        expirySec: 3600,
        timestamp: createdAt.millisecondsSinceEpoch ~/ 1000,
        paymentHash: 'payment\u202ehash',
        paymentSecret: 'not-retained',
        network: 'regtest',
      ),
    );
    when(
      () => wallet.sendBtc(
        amount: 1,
        address: 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
        feeRate: 1,
      ),
    ).thenAnswer((_) async => 'invalid\u200btxid');
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());
    const lightningRoute = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    const onchainRoute = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );

    await expectLater(
      engine.decodeInvoice(lightningRoute, 'lnbcrt1malformed'),
      throwsA(isA<NativeProtocolException>()),
    );
    await expectLater(
      engine.sendPayment(
        WalletSendCommand(
          route: onchainRoute,
          destination: 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
          amount: WalletAmount.onchain(
            assetId: WalletAsset.bitcoin.id,
            units: 1,
          ),
          feeRate: _feeRate(1),
        ),
      ),
      throwsA(isA<NativeProtocolException>()),
    );
  });

  test(
    'normalizes Bitcoin onchain and Lightning activity without leaking IDs',
    () async {
      final wallet = MockUtexoWallet();
      when(() => wallet.listTransactions()).thenAnswer(
        (_) async => <CoreTransaction>[
          const CoreTransaction(
            txid: 'incoming-txid',
            transactionType: 'Incoming',
            received: 5000,
            sent: 0,
            fee: 0,
            confirmationTime: CoreBlockTime(height: 100, timestamp: 1000),
          ),
          const CoreTransaction(
            txid: 'outgoing-txid',
            transactionType: 'SendBtc',
            received: 2000,
            sent: 10000,
            fee: 100,
          ),
        ],
      );
      when(() => wallet.listPayments()).thenAnswer(
        (_) async => <LightningPayment>[
          const LightningPayment(
            amtMsat: 2500,
            paymentHash: 'bitcoin-payment-hash',
            status: RlnPaymentStatuses.succeeded,
            inbound: true,
            createdAt: 2000,
          ),
          const LightningPayment(
            assetAmount: 10,
            assetId: 'other-rgb-asset',
            paymentHash: 'other-payment-hash',
            status: RlnPaymentStatuses.succeeded,
            inbound: false,
            createdAt: 3000,
          ),
        ],
      );
      final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

      final activities = await engine.listActivity(WalletAsset.bitcoin);

      expect(activities, hasLength(3));
      expect(activities[0].source, WalletActivitySource.lightningPayment);
      expect(activities[0].amount?.units, 2500);
      expect(activities[1].direction, WalletActivityDirection.received);
      expect(activities[1].amount?.units, 5000);
      expect(activities[1].confirmationHeight, 100);
      expect(activities[2].direction, WalletActivityDirection.sent);
      expect(activities[2].amount?.units, 7900);
      expect(activities[2].fee?.units, 100);
      expect(activities[2].occurredAt, isNull);
      for (final activity in activities) {
        expect(activity.id, matches(RegExp(r'^activity-[0-9a-f]{64}$')));
        expect(activity.id, isNot(contains('txid')));
        expect(activity.id, isNot(contains('payment-hash')));
      }
    },
  );

  test('normalizes configured RGB onchain and Lightning activity', () async {
    final wallet = MockUtexoWallet();
    final asset = WalletAsset.rgbUsdt(assetId: 'rgb-usdt', precision: 6);
    when(() => wallet.listTransfers(assetId: 'rgb-usdt')).thenAnswer(
      (_) async => <CoreTransfer>[
        CoreTransfer(
          idx: 7,
          batchTransferIdx: 8,
          createdAt: 1000,
          updatedAt: 1100,
          status: 'WaitingConfirmations',
          assignments: const <Assignment>[
            Assignment(type: 'Fungible', amount: 4),
            Assignment(type: 'Fungible', amount: 6),
          ],
          kind: 'Send',
          txid: 'rgb-anchor-txid',
          recipientId: 'rgb-recipient',
          receiveUtxo: const Outpoint(txid: 'receive-txid', vout: 1),
          changeUtxo: const Outpoint(txid: 'change-txid', vout: 2),
          expiration: 2000,
          transportEndpoints: const <CoreTransferTransportEndpoint>[
            CoreTransferTransportEndpoint(
              endpoint: 'https://proxy.example/secret-path',
              transportType: 'JsonRpc',
              used: true,
            ),
          ],
        ),
      ],
    );
    when(() => wallet.listPayments()).thenAnswer(
      (_) async => <LightningPayment>[
        const LightningPayment(
          assetAmount: 25,
          assetId: 'rgb-usdt',
          paymentHash: 'usdt-payment-hash',
          status: RlnPaymentStatuses.pending,
          inbound: false,
          createdAt: 3000,
          invoice: 'lnbcrt1rgbinvoice',
          payeePubkey: _nodePublicKey,
        ),
        const LightningPayment(
          assetAmount: 99,
          assetId: 'another-asset',
          paymentHash: 'another-payment-hash',
          status: RlnPaymentStatuses.succeeded,
        ),
      ],
    );
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    final activities = await engine.listActivity(asset);

    expect(activities, hasLength(2));
    expect(activities.first.rail, PaymentRail.lightning);
    expect(activities.first.amount?.units, 25);
    final transfer = activities.last;
    expect(transfer.operation, WalletActivityOperation.rgbSend);
    expect(transfer.amount?.units, 10);
    expect(transfer.status, WalletActivityStatus.waitingConfirmations);
    expect(transfer.receiveOutpoint, 'receive-txid:1');
    expect(transfer.changeOutpoint, 'change-txid:2');
    expect(transfer.transportEndpointCount, 1);
    expect(transfer.usedTransportEndpointCount, 1);
    expect(transfer.transportTypes, ['JsonRpc']);
    expect(transfer.toString(), isNot(contains('secret-path')));
  });

  test(
    'deduplicates identical activity and rejects conflicting records',
    () async {
      final wallet = MockUtexoWallet();
      when(() => wallet.listTransactions()).thenAnswer((_) async => const []);
      when(() => wallet.listPayments()).thenAnswer(
        (_) async => const <LightningPayment>[
          LightningPayment(
            amtMsat: 1000,
            paymentHash: 'duplicate-hash',
            status: RlnPaymentStatuses.pending,
          ),
          LightningPayment(
            amtMsat: 1000,
            paymentHash: 'duplicate-hash',
            status: RlnPaymentStatuses.pending,
          ),
        ],
      );
      final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

      expect(await engine.listActivity(WalletAsset.bitcoin), hasLength(1));

      when(() => wallet.listPayments()).thenAnswer(
        (_) async => const <LightningPayment>[
          LightningPayment(
            amtMsat: 1000,
            paymentHash: 'duplicate-hash',
            status: RlnPaymentStatuses.pending,
          ),
          LightningPayment(
            amtMsat: 2000,
            paymentHash: 'duplicate-hash',
            status: RlnPaymentStatuses.pending,
          ),
        ],
      );
      await expectLater(
        engine.listActivity(WalletAsset.bitcoin),
        throwsA(isA<NativeProtocolException>()),
      );
    },
  );

  test('fails closed for malformed fungible transfer amounts', () async {
    final wallet = MockUtexoWallet();
    final asset = WalletAsset.rgbUsdt(assetId: 'rgb-usdt', precision: 6);
    when(() => wallet.listTransfers(assetId: 'rgb-usdt')).thenAnswer(
      (_) async => <CoreTransfer>[
        CoreTransfer(
          idx: 1,
          status: 'Settled',
          assignments: const <Assignment>[Assignment(type: 'Fungible')],
          kind: 'ReceiveBlind',
          transportEndpoints: const <CoreTransferTransportEndpoint>[],
        ),
      ],
    );
    final engine = RgbWalletEngine(wallet, services, UtexoUnlockConfig());

    await expectLater(
      engine.listActivity(asset),
      throwsA(isA<NativeProtocolException>()),
    );
    verifyNever(() => wallet.listPayments());
  });
}

WalletFeeRateEstimate _feeRate(int satsPerVbyte) => WalletFeeRateEstimate(
  targetBlocks: 6,
  satsPerVbyte: satsPerVbyte,
  observedAt: DateTime.utc(2026, 8, 11),
);

String _regtestAddress() {
  final program = Uint8List.fromList(List<int>.generate(20, (index) => index));
  final words = Uint8List.fromList(<int>[
    0,
    ...bech32_codec.bech32.toWords(program),
  ]);
  return bech32_codec.bech32.encode(
    bech32_codec.Decoded(prefix: 'bcrt', words: words),
  );
}

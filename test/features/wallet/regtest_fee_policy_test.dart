import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

final class _Wallet extends Mock implements UtexoWallet {}

void main() {
  final now = DateTime.utc(2026, 10, 15);
  test(
    'regtest uses one sat/vbyte without asking native for a nonexistent market',
    () async {
      final wallet = _Wallet();
      when(() => wallet.estimateFeeRate(any()))
          .thenThrow(const RgbNodeError('CannotEstimateFees'));
      final engine = RgbWalletEngine(
        wallet,
        const WalletServiceConfiguration(
          environment: BlockchainEnvironment.regtest,
          sdkNetwork: 'regtest',
        ),
        UtexoUnlockConfig(),
        clock: () => now,
      );
      final rate = await engine.estimateFeeRate(6);
      expect(rate.satsPerVbyte, 1);
      expect(rate.source, WalletFeeRateSource.localRegtestPolicy);
      expect(rate.observedAt, now);
      expect(rate.targetBlocks, 6);
      expect(
        rate.isStaleAt(
          now.add(
            WalletFeeRateEstimate.maximumAge + const Duration(seconds: 1),
          ),
        ),
        isTrue,
      );
      await expectLater(
        engine.estimateFeeRate(0),
        throwsA(isA<WalletValidationException>()),
      );
      verifyZeroInteractions(wallet);
    },
  );

  for (final network in [
    BlockchainEnvironment.mainnet,
    BlockchainEnvironment.signet,
  ]) {
    test(
      '$network retains real native rates and never falls back after an error',
      () async {
        final wallet = _Wallet();
        final engine = RgbWalletEngine(
          wallet,
          WalletServiceConfiguration(
            environment: network,
            sdkNetwork: network == BlockchainEnvironment.signet
                ? 'utexo'
                : 'mainnet',
          ),
          UtexoUnlockConfig(),
          clock: () => now,
        );
        when(
          () => wallet.estimateFeeRate(6),
        ).thenAnswer((_) async => const FeeEstimationResponse(feeRate: 2.25));
        final rate = await engine.estimateFeeRate(6);
        expect(rate.satsPerVbyte, 3);
        expect(rate.source, WalletFeeRateSource.networkEstimate);
        final failure = const RgbNodeError('CannotEstimateFees');
        when(() => wallet.estimateFeeRate(6)).thenThrow(failure);
        await expectLater(engine.estimateFeeRate(6), throwsA(same(failure)));
        verify(() => wallet.estimateFeeRate(6)).called(2);
      },
    );
  }

  test('rate equality and persisted review bind the source', () {
    final network = WalletFeeRateEstimate(
      targetBlocks: 6,
      satsPerVbyte: 1,
      observedAt: now,
    );
    final local = WalletFeeRateEstimate(
      targetBlocks: 6,
      satsPerVbyte: 1,
      observedAt: now,
      source: WalletFeeRateSource.localRegtestPolicy,
    );
    expect(local, isNot(network));
    expect({local, network}, hasLength(2));
    expect(
      local.hashCode,
      Object.hash(
        local.targetBlocks,
        local.satsPerVbyte,
        local.observedAt,
        local.source,
      ),
    );
    expect(
      () => WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: now,
        source: WalletFeeRateSource.localRegtestPolicy,
      ),
      throwsArgumentError,
    );
    final review = RgbWalletSetupReview(
      id: '1' * 32,
      walletId: '2' * 32,
      network: BlockchainEnvironment.regtest,
      runtimeFingerprint: '3' * 64,
      nodePublicKey: '02${'4' * 64}',
      feeRateSatPerVbyte: 1,
      expiresAt: now.add(RgbWalletSetupReview.lifetime),
      feeSource: local.source,
    );
    expect(
      RgbWalletSetupReview.fromJson(review.toJson()).feeSource,
      WalletFeeRateSource.localRegtestPolicy,
    );
    expect(
      () => RgbWalletSetupReview(
        id: review.id,
        walletId: review.walletId,
        network: BlockchainEnvironment.mainnet,
        runtimeFingerprint: review.runtimeFingerprint,
        nodePublicKey: review.nodePublicKey,
        feeRateSatPerVbyte: 1,
        expiresAt: review.expiresAt,
        feeSource: WalletFeeRateSource.localRegtestPolicy,
      ),
      throwsA(isA<StoredDataCorruptionException>()),
    );
  });
}

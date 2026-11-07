import 'package:aster/core/config/config.dart';
import 'package:aster/core/errors/errors.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'on-chain health preserves unavailable tip and Lightning observations',
    () {
      final status = WalletNetworkStatus(
        environment: BlockchainEnvironment.signet,
        blockHeight: null,
        nodePublicKey: null,
        channelCount: null,
        usableChannelCount: null,
        peerCount: null,
        walletIdentity: 'a' * 64,
      );
      expect(status.blockHeight, isNull);
      expect(status.nodePublicKey, isNull);
      expect(status.channelCount, isNull);
      expect(status.usableChannelCount, isNull);
      expect(status.peerCount, isNull);
      expect(status.publicIdentity, 'a' * 64);
      expect(
        () => WalletNetworkStatus(
          environment: BlockchainEnvironment.signet,
          blockHeight: null,
          nodePublicKey: null,
          channelCount: null,
          usableChannelCount: null,
          peerCount: null,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'native recovered fee is historical evidence and cannot authorize setup',
    () {
      final recovered = WalletFeeRateEstimate(
        targetBlocks: null,
        satsPerVbyte: 1,
        observedAt: DateTime.utc(2026),
        source: WalletFeeRateSource.nativeRecovery,
      );
      expect(recovered.isStaleAt(DateTime.utc(2026)), isTrue);
      expect(
        () => WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 1,
          observedAt: DateTime.utc(2026),
          source: WalletFeeRateSource.nativeRecovery,
        ),
        throwsArgumentError,
      );
      expect(
        () => RgbWalletSetupReview(
          id: 'a' * 32,
          walletId: 'b' * 32,
          network: BlockchainEnvironment.regtest,
          runtimeFingerprint: 'c' * 64,
          nodePublicKey: 'd' * 64,
          identityKind: RgbSetupIdentityKind.nativeWallet,
          feeRateSatPerVbyte: 1,
          expiresAt: DateTime.utc(2030),
          feeSource: WalletFeeRateSource.nativeRecovery,
        ),
        throwsA(isA<StoredDataCorruptionException>()),
      );
    },
  );

  test('preparation binds a native wallet identity with an explicit kind', () {
    final review = RgbWalletSetupReview(
      id: 'a' * 32,
      walletId: 'b' * 32,
      network: BlockchainEnvironment.regtest,
      runtimeFingerprint: 'c' * 64,
      nodePublicKey: 'd' * 64,
      identityKind: RgbSetupIdentityKind.nativeWallet,
      feeRateSatPerVbyte: 1,
      expiresAt: DateTime.utc(2030),
    );
    final restored = RgbWalletSetupReview.fromJson(review.toJson());
    expect(restored.nodePublicKey, 'd' * 64);
    expect(restored.identityKind, RgbSetupIdentityKind.nativeWallet);
    expect(restored.toJson(), review.toJson());
    expect(
      () => RgbWalletSetupReview.fromJson({
        ...review.toJson(),
        'identityKind': 'lightningNode',
      }),
      throwsA(isA<StoredDataCorruptionException>()),
    );
    final legacy = RgbWalletSetupReview(
      id: 'a' * 32,
      walletId: 'b' * 32,
      network: BlockchainEnvironment.regtest,
      runtimeFingerprint: 'c' * 64,
      nodePublicKey: '02${'d' * 64}',
      feeRateSatPerVbyte: 1,
      expiresAt: DateTime.utc(2030),
    );
    expect(legacy.toJson(), isNot(contains('identityKind')));
    expect(
      RgbWalletSetupReview.fromJson(legacy.toJson()).identityKind,
      RgbSetupIdentityKind.lightningNode,
    );
  });
}

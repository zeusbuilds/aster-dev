import '../../../../core/config/app_environment.dart';
import '../../../../core/config/signet_deployment.dart';
import '../../../../core/errors/errors.dart';
import 'wallet_fee.dart';

/// Identifies the native owner bound into one reviewed preparation.
enum RgbSetupIdentityKind { lightningNode, nativeWallet }

bool _validSetupIdentity(String value, RgbSetupIdentityKind kind) =>
    switch (kind) {
      RgbSetupIdentityKind.lightningNode => RegExp(
        r'^(02|03)[a-f0-9]{64}$',
      ).hasMatch(value),
      RgbSetupIdentityKind.nativeWallet => RegExp(
        r'^[a-f0-9]{64}$',
      ).hasMatch(value),
    };

/// Reviewed wallet-owned outputs. The rate is authorized, not a total fee cap.
final class RgbWalletSetupReview {
  RgbWalletSetupReview({
    required this.id,
    required this.walletId,
    required this.network,
    required this.runtimeFingerprint,
    required this.nodePublicKey,
    this.identityKind = RgbSetupIdentityKind.lightningNode,
    required this.feeRateSatPerVbyte,
    required this.expiresAt,
    this.feeSource = WalletFeeRateSource.networkEstimate,
  }) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(walletId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(runtimeFingerprint) ||
        !_validSetupIdentity(nodePublicKey, identityKind) ||
        feeRateSatPerVbyte < 1 ||
        feeRateSatPerVbyte > 1000000 ||
        !expiresAt.isUtc ||
        feeSource == WalletFeeRateSource.nativeRecovery ||
        (feeSource == WalletFeeRateSource.localRegtestPolicy &&
            (network != BlockchainEnvironment.regtest ||
                feeRateSatPerVbyte != 1)) ||
        (feeSource == WalletFeeRateSource.devSignetPolicy &&
            (network != BlockchainEnvironment.signet ||
                identityKind != RgbSetupIdentityKind.nativeWallet ||
                feeRateSatPerVbyte !=
                    UtexoDevSignetPolicy.fallbackFeeSatsPerVbyte))) {
      throw const StoredDataCorruptionException();
    }
  }

  static const outputCount = 4;
  static const outputValueSats = 20000;
  static const lifetime = Duration(minutes: 2);
  final String id;
  final String walletId;
  final BlockchainEnvironment network;
  final String runtimeFingerprint;

  /// Legacy JSON field name; interpreted only with [identityKind].
  final String nodePublicKey;
  final RgbSetupIdentityKind identityKind;
  final int feeRateSatPerVbyte;
  final DateTime expiresAt;
  final WalletFeeRateSource feeSource;

  Map<String, Object?> toJson() => {
    'id': id,
    'walletId': walletId,
    'network': network.name,
    'runtimeFingerprint': runtimeFingerprint,
    'nodePublicKey': nodePublicKey,
    if (identityKind != RgbSetupIdentityKind.lightningNode)
      'identityKind': identityKind.name,
    'feeRate': feeRateSatPerVbyte,
    'feeSource': feeSource.name,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    'count': outputCount,
    'size': outputValueSats,
  };

  factory RgbWalletSetupReview.fromJson(Map<String, Object?> json) {
    if (json.keys.toSet().difference({
          'id',
          'walletId',
          'network',
          'runtimeFingerprint',
          'nodePublicKey',
          'identityKind',
          'feeRate',
          'feeSource',
          'expiresAt',
          'count',
          'size',
        }).isNotEmpty ||
        json.length != (json.containsKey('identityKind') ? 11 : 10) ||
        (json.containsKey('identityKind') &&
            json['identityKind'] != 'nativeWallet') ||
        json['count'] != outputCount ||
        json['size'] != outputValueSats ||
        json['id'] is! String ||
        json['walletId'] is! String ||
        json['network'] is! String ||
        json['runtimeFingerprint'] is! String ||
        json['nodePublicKey'] is! String ||
        json['feeRate'] is! int ||
        json['feeSource'] is! String ||
        json['expiresAt'] is! int) {
      throw const StoredDataCorruptionException();
    }
    return RgbWalletSetupReview(
      id: json['id']! as String,
      walletId: json['walletId']! as String,
      network: BlockchainEnvironment.parse(json['network']! as String),
      runtimeFingerprint: json['runtimeFingerprint']! as String,
      nodePublicKey: json['nodePublicKey']! as String,
      identityKind: json.containsKey('identityKind')
          ? RgbSetupIdentityKind.nativeWallet
          : RgbSetupIdentityKind.lightningNode,
      feeRateSatPerVbyte: json['feeRate']! as int,
      feeSource: WalletFeeRateSource.values.byName(
        json['feeSource']! as String,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        json['expiresAt']! as int,
        isUtc: true,
      ),
    );
  }
}

enum RgbWalletSetupPhase { required, ready, pending, indeterminate }

final class RgbWalletSetupStatus {
  const RgbWalletSetupStatus(this.phase, {this.transactionId});
  final RgbWalletSetupPhase phase;
  final String? transactionId;
}

/// Native availability is a candidate; invoice creation still reserves a slot.
final class RgbWalletSetupInventory {
  RgbWalletSetupInventory({
    required this.freeAllocationCount,
    required this.vanillaSpendableSats,
    required this.runtimeFingerprint,
    required this.nodePublicKey,
    this.identityKind = RgbSetupIdentityKind.lightningNode,
  }) {
    if (freeAllocationCount < 0 ||
        freeAllocationCount > 10000 ||
        vanillaSpendableSats < 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(runtimeFingerprint) ||
        !_validSetupIdentity(nodePublicKey, identityKind)) {
      throw const StoredDataCorruptionException();
    }
  }

  /// Simple empty-output candidates only. Zero never proves native RGB
  /// allocation capacity is exhausted; only a real native receive can do that.
  final int freeAllocationCount;
  final int vanillaSpendableSats;
  final String runtimeFingerprint;

  /// Legacy field name retained for stored RLN reviews.
  final String nodePublicKey;
  final RgbSetupIdentityKind identityKind;
}

final class RgbWalletSetupTransaction {
  RgbWalletSetupTransaction({required this.txid, required this.confirmed}) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(txid)) {
      throw const StoredDataCorruptionException();
    }
  }
  final String txid;
  final bool confirmed;
}

const rgbWalletSetupRequiredFailure = AppFailure(
  code: 'rgb_wallet_setup_required',
  kind: AppFailureKind.unavailable,
  userMessage: 'Prepare wallet-owned RGB outputs before receiving USDT. This requires a separate Bitcoin transaction and network fee.',
  retryable: false,
);

const rgbWalletSetupPendingFailure = AppFailure(
  code: 'rgb_wallet_setup_pending',
  kind: AppFailureKind.conflict,
  userMessage: 'RGB wallet preparation is unresolved. Check its status before another on-chain action. Do not submit it again.',
  retryable: false,
);

import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/errors.dart';
import '../../../wallet/data/validation/bitcoin_payment_instruction_parser.dart';
import '../../../wallet/domain/models/models.dart';
import '../../domain/models/models.dart';

/// Read-only payment recognition before a QR can leave the camera surface.
///
/// Bitcoin validation is local. RGB uses the same authoritative decoder as Send;
/// it never creates an invoice, reserves outputs, or submits a payment. The
/// caller owns lifecycle and wallet-generation checks around this operation.
final class ScanPaymentValidator {
  ScanPaymentValidator({
    required this.environment,
    required this.previewRgb,
    required this.now,
  });

  final BlockchainEnvironment environment;
  final Future<AppResult<WalletPaymentPreview>> Function(String) previewRgb;
  final DateTime Function() now;
  bool _rgbReadPending = false;

  Future<bool> accepts(ScanPayload payload) async {
    final value = payload.value;
    if (const BitcoinPaymentInstructionParser().decodeOnchain(
      value,
      environment,
    ) is AppSuccess<BitcoinDestination>) {
      return true;
    }
    // Ordinary text, website QRs, and release-disabled Lightning never cross
    // the native boundary. Do not infer an RGB asset or chain from its prefix.
    if (!value.toLowerCase().startsWith('rgb:')) return false;
    // A timeout in the camera owner cannot cancel native work. Keep at most
    // one underlying RGB read alive; later frames must not build a native queue.
    // Bitcoin remains local and available while that read is pending.
    if (_rgbReadPending) return false;
    _rgbReadPending = true;
    try {
      final decoded = await previewRgb(value);
      return switch (decoded) {
        AppSuccess<WalletPaymentPreview>(:final value) =>
          value.route.target == WalletPaymentTarget.usdtOnchain &&
              !value.isExpiredAt(now()),
        AppFailureResult<WalletPaymentPreview>() => false,
      };
    } finally {
      _rgbReadPending = false;
    }
  }
}

import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/widgets/wallet_asset_icon.dart';

/// Accessible Receive QR surface with a non-secret encoder fallback.
final class ReceiveRequestQr extends StatefulWidget {
  const ReceiveRequestQr({
    super.key,
    required this.encodedRequest,
    required this.semanticLabel,
    this.assetKind,
  });

  final String encodedRequest;
  final String semanticLabel;
  final WalletAssetKind? assetKind;

  @override
  State<ReceiveRequestQr> createState() => _ReceiveRequestQrState();
}

final class _ReceiveRequestQrState extends State<ReceiveRequestQr> {
  QrImage? _image;

  @override
  void initState() {
    super.initState();
    _encode();
  }

  @override
  void didUpdateWidget(ReceiveRequestQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.encodedRequest != widget.encodedRequest) _encode();
  }

  void _encode() {
    try {
      _image = QrImage(
        QrCode.fromData(
          data: widget.encodedRequest,
          errorCorrectLevel: QrErrorCorrectLevel.H,
        ),
      );
    } on Exception {
      _image = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return _buildFailure(context);
    return Semantics(
      image: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.all(context.spacing.lg),
        child: Stack(
          alignment: Alignment.center,
          children: [
            PrettyQrView(
              qrImage: image,
              decoration: PrettyQrDecoration(
                shape: PrettyQrDotsSymbol(color: context.colorScheme.onSurface),
              ),
            ),
            if (widget.assetKind case final kind?)
              FractionallySizedBox(
                widthFactor: context.metrics.qrLogoSizeFactor,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(context.spacing.xs),
                    child: LayoutBuilder(
                      builder: (context, constraints) => WalletAssetIcon(
                        kind: kind,
                        size: constraints.maxWidth,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailure(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Payment request QR code unavailable',
      excludeSemantics: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.qr_code_2,
              size: context.icons.xl,
              color: context.appColors.textSecondary,
            ),
            SizedBox(height: context.spacing.sm),
            Text(
              'QR unavailable',
              style: context.type.statusMessage,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

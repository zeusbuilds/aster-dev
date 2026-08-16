import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../shared/shared.dart';

/// Accessible Receive QR surface with a non-secret encoder fallback.
final class ReceiveRequestQr extends StatefulWidget {
  const ReceiveRequestQr({
    super.key,
    required this.encodedRequest,
    required this.semanticLabel,
  });

  final String encodedRequest;
  final String semanticLabel;

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
          errorCorrectLevel: QrErrorCorrectLevel.L,
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
        child: PrettyQrView(
          qrImage: image,
          decoration: PrettyQrDecoration(
            shape: PrettyQrDotsSymbol(color: context.colorScheme.onSurface),
          ),
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

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../shared/shared.dart';

/// Full-screen camera preview with barcode detection; filters by cutout (focus area).
class ScanCameraWidget extends StatefulWidget {
  const ScanCameraWidget({
    super.key,
    required this.controller,
    required this.cutoutRect,
    required this.screenSize,
    required this.flashOn,
    required this.zoomFactor,
    required this.onScanned,
    required this.onPermissionDenied,
    required this.onError,
    this.onCameraReady,
  });

  final MobileScannerController controller;
  final Rect cutoutRect;
  final Size screenSize;
  final bool flashOn;

  /// Current zoom factor from device range (e.g. 1.0, 2.0).
  final double zoomFactor;
  final void Function(String value) onScanned;
  final VoidCallback onPermissionDenied;
  final void Function(String message) onError;

  /// Called when camera is initialized with min and max zoom factors (e.g. 1.0, 4.0).
  final void Function(double minZoom, double maxZoom)? onCameraReady;

  @override
  State<ScanCameraWidget> createState() => _ScanCameraWidgetState();
}

class _ScanCameraWidgetState extends State<ScanCameraWidget>
    with WidgetsBindingObserver {
  String? _errorMessage;
  bool _hasReportedCameraReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onCameraReady?.call(1.0, 3.0);
      _hasReportedCameraReady = true;
    });
  }

  Future<void> _setTorch(bool enabled) async {
    try {
      final torchIsOn = widget.controller.value.torchState == TorchState.on;
      if (torchIsOn != enabled) {
        await widget.controller.toggleTorch();
      }
    } on Exception {
      if (mounted) widget.onError('The flashlight is unavailable.');
    }
  }

  Future<void> _setZoomFactor(double factor) async {
    try {
      final normalizedZoom = ((factor - 1.0) / 2.0).clamp(0.0, 1.0);
      await widget.controller.setZoomScale(normalizedZoom);
    } on Exception {
      if (mounted) widget.onError('Camera zoom is unavailable.');
    }
  }

  @override
  void didUpdateWidget(ScanCameraWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flashOn != widget.flashOn) {
      unawaited(_setTorch(widget.flashOn));
    }
    if (oldWidget.zoomFactor != widget.zoomFactor) {
      unawaited(_setZoomFactor(widget.zoomFactor));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (_errorMessage != null) {
      return ColoredBox(color: colors.scanOverlayBase);
    }

    return MobileScanner(
      controller: widget.controller,
      fit: BoxFit.cover,
      scanWindow: widget.cutoutRect,
      placeholderBuilder: (_) => ColoredBox(color: colors.scanOverlayBase),
      errorBuilder: (context, error) {
        if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
          widget.onPermissionDenied();
        } else {
          final message = error.errorDetails?.message ?? error.toString();
          _errorMessage = message;
          widget.onError(message);
        }
        return ColoredBox(color: colors.scanOverlayBase);
      },
      onDetect: (capture) {
        if (!_hasReportedCameraReady) {
          widget.onCameraReady?.call(1.0, 3.0);
          _hasReportedCameraReady = true;
        }
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw == null || raw.isEmpty) continue;
          widget.onScanned(raw);
          return;
        }
      },
      onDetectError: (error, stackTrace) {
        final message = error.toString();
        widget.onError(message);
      },
    );
  }
}

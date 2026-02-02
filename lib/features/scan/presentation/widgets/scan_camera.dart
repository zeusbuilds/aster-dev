import 'dart:async';

import 'package:aster/shared/shared.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:aster/features/scan/data/data.dart';

/// Fallback preview dimensions when [CameraController.value.previewSize] is null (VGA).
const double _kCameraPreviewFallbackWidth = 480;
const double _kCameraPreviewFallbackHeight = 480;

/// Full-screen camera preview with barcode detection; filters by cutout (focus area).
class ScanCameraWidget extends StatefulWidget {
  const ScanCameraWidget({
    super.key,
    required this.cutoutRect,
    required this.screenSize,
    required this.flashOn,
    required this.zoomFactor,
    required this.onScanned,
    required this.onPermissionDenied,
    required this.onError,
    this.onCameraReady,
  });

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
  ScannerService? _service;
  StreamSubscription<String>? _barcodeSubscription;
  bool _initialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startService();
  }

  Future<void> _startService() async {
    try {
      final service = ScannerService(
        cutoutRect: widget.cutoutRect,
        screenSize: widget.screenSize,
      );
      await service.start();
      if (!mounted) return;
      _service = service;
      _barcodeSubscription = service.barcodeStream.listen((raw) {
        if (mounted) widget.onScanned(raw);
      });
      widget.onCameraReady?.call(
        await service.getMinZoomLevel(),
        await service.getMaxZoomLevel(),
      );
      if (!mounted) return;
      await service.setZoomFactor(widget.zoomFactor);
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _errorMessage = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      if (e.code == 'CameraAccessDenied' ||
          e.description?.contains('permission') == true) {
        widget.onPermissionDenied();
      } else {
        setState(() => _errorMessage = e.description ?? e.code);
        widget.onError(e.description ?? e.code);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
      widget.onError(e.toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_service == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _service!.stop().then((_) {
          if (mounted) setState(() {});
        });
        break;
      case AppLifecycleState.resumed:
        _service!.start().then((_) {
          if (mounted) setState(() {});
        });
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void didUpdateWidget(ScanCameraWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_service != null) {
      if (oldWidget.flashOn != widget.flashOn) {
        _service!.setFlashMode(widget.flashOn);
      }
      if (oldWidget.zoomFactor != widget.zoomFactor) {
        _service!.setZoomFactor(widget.zoomFactor);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _barcodeSubscription?.cancel();
    _service?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (_errorMessage != null) {
      return ColoredBox(color: colors.fill6);
    }

    if (!_initialized || _service?.controller == null) {
      return ColoredBox(color: colors.fill6);
    }

    final controller = _service!.controller!;
    final previewSize = controller.value.previewSize;
    final width = previewSize?.height ?? _kCameraPreviewFallbackWidth;
    final height = previewSize?.width ?? _kCameraPreviewFallbackHeight;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width.toDouble(),
          height: height.toDouble(),
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Service that owns camera and ML Kit barcode scanner.
///
/// Handles permission, start/stop, image stream → InputImage → detection,
/// and filters results by cutout (focus area). Created and disposed by the
/// camera widget.
class ScannerService {
  ScannerService({required this.cutoutRect, required this.screenSize});

  final Rect cutoutRect;
  final Size screenSize;

  CameraController? _controller;
  BarcodeScanner? _barcodeScanner;
  StreamController<String>? _barcodeController;
  bool _disposed = false;
  DateTime? _lastProcessedAt;
  static const _throttleMs = 250;

  CameraController? get controller => _controller;

  /// Stream of barcode raw values (only those inside the cutout).
  Stream<String> get barcodeStream {
    _barcodeController ??= StreamController<String>.broadcast();
    return _barcodeController!.stream;
  }

  /// Whether the service is ready (camera initialized).
  bool get isInitialized =>
      _controller != null && _controller!.value.isInitialized;

  /// Start camera and barcode detection.
  Future<void> start() async {
    if (_disposed) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _controller = CameraController(
        back,
        ResolutionPreset.ultraHigh,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (_disposed) return;
      _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]);
      _lastProcessedAt = null;
      await _controller!.startImageStream(_onImage);
    } catch (e) {
      rethrow;
    }
  }

  void _onImage(CameraImage image) {
    if (_disposed || _barcodeScanner == null || _barcodeController == null) {
      return;
    }
    final now = DateTime.now();
    if (_lastProcessedAt != null &&
        now.difference(_lastProcessedAt!).inMilliseconds < _throttleMs) {
      return;
    }
    _lastProcessedAt = now;
    _processImage(image);
  }

  Future<void> _processImage(CameraImage image) async {
    if (_disposed || _barcodeScanner == null) return;
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;
      final barcodes = await _barcodeScanner!.processImage(inputImage);
      if (_disposed) return;
      final controller = _barcodeController;
      if (controller == null || controller.isClosed) return;
      for (final barcode in barcodes) {
        final raw = barcode.rawValue;
        if (raw == null || raw.isEmpty) continue;
        final box = barcode.boundingBox;
        if (_isInCutout(box, image.width, image.height)) {
          controller.add(raw);
          return;
        }
      }
    } catch (_) {
      // Ignore per-frame errors
    }
  }

  bool _isInCutout(Rect box, int imageWidth, int imageHeight) {
    if (imageWidth <= 0 || imageHeight <= 0) return true;
    final screenW = screenSize.width;
    final screenH = screenSize.height;
    final scale = (screenW / imageWidth) > (screenH / imageHeight)
        ? screenW / imageWidth
        : screenH / imageHeight;
    final offsetX = (imageWidth * scale - screenW) / 2;
    final offsetY = (imageHeight * scale - screenH) / 2;
    final left = (cutoutRect.left + offsetX) / scale;
    final top = (cutoutRect.top + offsetY) / scale;
    final cutoutInImageRect = Rect.fromLTWH(
      left.clamp(0.0, imageWidth.toDouble()),
      top.clamp(0.0, imageHeight.toDouble()),
      (cutoutRect.width / scale).clamp(0.0, imageWidth.toDouble() - left),
      (cutoutRect.height / scale).clamp(0.0, imageHeight.toDouble() - top),
    );
    return cutoutInImageRect.overlaps(box);
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    try {
      final format = Platform.isAndroid
          ? InputImageFormat.nv21
          : InputImageFormat.bgra8888;
      final rotation = InputImageRotation.rotation0deg;
      final bytesPerRow = image.planes.isNotEmpty
          ? image.planes[0].bytesPerRow
          : image.width;
      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      );
      final bytes = _getBytesFromCameraImage(image);
      if (bytes == null) return null;
      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _getBytesFromCameraImage(CameraImage image) {
    if (Platform.isAndroid) {
      final y = image.planes[0].bytes;
      final vu = image.planes.length > 1 ? image.planes[1].bytes : <int>[];
      return Uint8List.fromList(y + vu);
    }
    if (image.planes.length == 1) {
      return Uint8List.fromList(image.planes[0].bytes);
    }
    return null;
  }

  /// Stop image stream and release camera.
  ///
  /// Uses a local reference so concurrent calls (e.g. lifecycle + dispose)
  /// never use a null or already-disposed controller.
  Future<void> stop() async {
    final controller = _controller;
    _controller = null;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    } catch (_) {
      // Ignore if already disposed or stream already stopped.
    }
  }

  /// Set flash mode (torch on/off).
  Future<void> setFlashMode(bool on) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    await _controller!.setFlashMode(on ? FlashMode.torch : FlashMode.off);
  }

  /// Min zoom factor (e.g. 1.0). Use after camera is initialized.
  Future<double> getMinZoomLevel() async {
    if (_controller == null || !_controller!.value.isInitialized) return 1.0;
    try {
      return await _controller!.getMinZoomLevel();
    } catch (_) {
      return 1.0;
    }
  }

  /// Max zoom factor (e.g. 4.0). Use after camera is initialized.
  Future<double> getMaxZoomLevel() async {
    if (_controller == null || !_controller!.value.isInitialized) return 1.0;
    try {
      return await _controller!.getMaxZoomLevel();
    } catch (_) {
      return 1.0;
    }
  }

  /// Set zoom to an actual factor from the device range (e.g. 1.0, 2.0).
  /// Clamps to device min/max. Prefer this over [setZoomLevel] for device-aligned zoom.
  Future<void> setZoomFactor(double factor) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final maxZoom = await _controller!.getMaxZoomLevel();
      final minZoom = await _controller!.getMinZoomLevel();
      final value = factor.clamp(minZoom, maxZoom);
      await _controller!.setZoomLevel(value);
    } catch (_) {}
  }

  /// Set zoom level if supported (0.0–1.0 normalized). Prefer [setZoomFactor] for device steps.
  Future<void> setZoomLevel(double level) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final maxZoom = await _controller!.getMaxZoomLevel();
      final minZoom = await _controller!.getMinZoomLevel();
      final value = minZoom + (maxZoom - minZoom) * level.clamp(0.0, 1.0);
      await _controller!.setZoomLevel(value);
    } catch (_) {}
  }

  /// Dispose the service and close the barcode stream.
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _barcodeScanner?.close();
    _barcodeScanner = null;
    await _barcodeController?.close();
    _barcodeController = null;
  }
}

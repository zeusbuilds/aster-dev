import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';
import 'scan_session.dart';
import 'scan_session_contract.dart';

/// Production factory for isolated `mobile_scanner` / `image_picker` sessions.
final class MobileScanSessionFactory implements ScanSessionFactory {
  MobileScanSessionFactory({required this.validatePayload, this.contextToken});

  final Future<bool> Function(ScanPayload) validatePayload;
  final Object? Function()? contextToken;

  final ScanSessionCommandQueue _commandQueue = ScanSessionCommandQueue();

  @override
  ScanSession create() {
    final controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
      formats: const [BarcodeFormat.qrCode],
      returnImage: false,
      initialZoom: 0,
    );
    return ManagedScanSession(
      MobileScannerCameraDriver(controller),
      ImagePickerScanGallery(ImagePicker()),
      commandQueue: _commandQueue,
      validatePayload: validatePayload,
      contextToken: contextToken,
    );
  }
}

/// The only adapter that owns `mobile_scanner` types.
final class MobileScannerCameraDriver extends ChangeNotifier
    implements ScanCameraDriver {
  MobileScannerCameraDriver(this._controller) {
    _controller.addListener(_notifyControllerState);
  }

  final MobileScannerController _controller;
  bool _disposed = false;
  ScanZoomRange? _zoom;
  double? _preferredZoomRatio;

  @override
  ScanDriverState get state {
    final value = _controller.value;
    return ScanDriverState(
      isInitialized: value.isInitialized,
      isRunning: value.isRunning,
      torchAvailable: value.torchState != TorchState.unavailable,
      torchOn: value.torchState == TorchState.on,
      zoom: value.isInitialized && value.isRunning ? _zoom : null,
    );
  }

  @override
  Widget buildView({
    required Rect scanWindow,
    required Color placeholderColor,
    required ValueChanged<Iterable<String?>> onDetected,
    required ValueChanged<ScanDriverException> onFailure,
  }) {
    return MobileScanner(
      controller: _controller,
      fit: BoxFit.cover,
      scanWindow: scanWindow,
      scanWindowUpdateThreshold: 1,
      useAppLifecycleState: false,
      placeholderBuilder: (_) => ColoredBox(color: placeholderColor),
      errorBuilder: (context, error) {
        final failure = _mapScannerException(error, StackTrace.current);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) onFailure(failure);
        });
        return ColoredBox(color: placeholderColor);
      },
      onDetect: (capture) =>
          onDetected(capture.barcodes.map((barcode) => barcode.rawValue)),
      onDetectError: (error, stackTrace) =>
          onFailure(_mapUnknown(error, stackTrace, 'scan_detection_failed')),
    );
  }

  @override
  Future<void> start() async {
    _zoom = null;
    await _guard('scan_camera_start_failed', _controller.start);
    final state = _controller.value;
    final error = state.error;
    if (error != null) {
      throw _mapScannerException(error, StackTrace.current);
    }
    if (!state.isRunning) {
      throw const ScanDriverException(
        code: 'scan_camera_start_incomplete',
        kind: ScanDriverFailureKind.invalidState,
      );
    }
    // Zoom is optional. An unsupported capability read must never prevent QR
    // capture, trigger camera restarts, or fabricate a magnification label.
    try {
      var zoom = _cameraZoom(await _controller.getZoomState());
      final desired = (_preferredZoomRatio ?? 1).clamp(
        zoom.minimum,
        zoom.maximum,
      );
      if ((zoom.current - desired).abs() > 0.001) {
        try {
          zoom = _cameraZoom(await _controller.setZoomRatio(desired));
        } catch (_) {
          // A failed default leaves the camera's last confirmed ratio intact.
        }
      }
      if (!_disposed && _controller.value.isRunning) {
        _zoom = zoom;
        _preferredZoomRatio = zoom.current;
      }
    } catch (_) {
      _zoom = null;
    }
    _notifyControllerState();
  }

  @override
  Future<void> stop() async {
    await _guard('scan_camera_stop_failed', _controller.stop);
    if (_controller.value.isRunning) {
      throw const ScanDriverException(
        code: 'scan_camera_stop_incomplete',
        kind: ScanDriverFailureKind.invalidState,
      );
    }
  }

  @override
  Future<void> setTorchEnabled(bool enabled) async {
    final current = _controller.value.torchState;
    if (current == TorchState.unavailable || !_controller.value.isRunning) {
      throw const ScanDriverException(
        code: 'scan_torch_unavailable',
        kind: ScanDriverFailureKind.invalidState,
      );
    }
    final isOn = current == TorchState.on;
    if (isOn == enabled) return;
    await _guard('scan_torch_failed', _controller.toggleTorch);
  }

  @override
  Future<void> setZoomRatio(double ratio) async {
    await _guard('scan_zoom_failed', () async {
      final applied = _cameraZoom(await _controller.setZoomRatio(ratio));
      if (_disposed || !_controller.value.isRunning) return;
      _zoom = applied;
      _preferredZoomRatio = applied.current;
      notifyListeners();
    });
  }

  static ScanZoomRange _cameraZoom(CameraZoomState state) {
    final zoom = ScanZoomRange(
      minimum: state.minZoomRatio,
      maximum: state.maxZoomRatio,
      current: state.zoomRatio,
    );
    if (!zoom.isValid) {
      throw const ScanDriverException(
        code: 'scan_zoom_state_invalid',
        kind: ScanDriverFailureKind.invalidState,
      );
    }
    return zoom;
  }

  @override
  Future<Iterable<String?>> analyzeImage(String path) async {
    try {
      final capture = await _controller.analyzeImage(
        path,
        formats: const [BarcodeFormat.qrCode],
      );
      return capture?.barcodes.map((barcode) => barcode.rawValue) ?? const [];
    } on UnsupportedError catch (error, stackTrace) {
      throw ScanDriverException(
        code: 'scan_gallery_unsupported',
        kind: ScanDriverFailureKind.unsupported,
        diagnostic: FailureMapper.diagnosticCause(error),
        stackTrace: stackTrace,
      );
    } on MobileScannerException catch (error, stackTrace) {
      throw _mapScannerException(error, stackTrace, gallery: true);
    } catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, 'scan_gallery_analysis_failed');
    }
  }

  Future<void> _guard(
    String fallbackCode,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } on MobileScannerException catch (error, stackTrace) {
      throw _mapScannerException(error, stackTrace);
    } catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, fallbackCode);
    }
  }

  void _notifyControllerState() {
    if (_disposed) return;
    if (!_controller.value.isInitialized || !_controller.value.isRunning) {
      _zoom = null;
    }
    notifyListeners();
  }

  @override
  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_notifyControllerState);
    try {
      await _controller.dispose();
    } on MobileScannerException catch (error, stackTrace) {
      throw _mapScannerException(error, stackTrace);
    } catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, 'scan_camera_dispose_failed');
    } finally {
      super.dispose();
    }
  }

  static ScanDriverException _mapScannerException(
    MobileScannerException error,
    StackTrace stackTrace, {
    bool gallery = false,
  }) {
    final kind = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        ScanDriverFailureKind.permissionDenied,
      MobileScannerErrorCode.unsupported => ScanDriverFailureKind.unsupported,
      MobileScannerErrorCode.controllerAlreadyInitialized ||
      MobileScannerErrorCode.controllerInitializing ||
      MobileScannerErrorCode.controllerNotAttached ||
      MobileScannerErrorCode.controllerUninitialized =>
        ScanDriverFailureKind.invalidState,
      MobileScannerErrorCode.controllerDisposed ||
      MobileScannerErrorCode.genericError => ScanDriverFailureKind.unavailable,
    };
    return ScanDriverException(
      code: gallery ? 'scan_gallery_analysis_failed' : 'scan_camera_failed',
      kind: kind,
      diagnostic: FailureMapper.diagnosticCause(error),
      stackTrace: stackTrace,
    );
  }

  static ScanDriverException _mapUnknown(
    Object error,
    StackTrace stackTrace,
    String code,
  ) {
    return ScanDriverException(
      code: code,
      kind: ScanDriverFailureKind.unavailable,
      diagnostic: FailureMapper.diagnosticCause(error),
      stackTrace: stackTrace,
    );
  }
}

/// The only adapter that owns `image_picker` types and Android lost-data policy.
final class ImagePickerScanGallery implements ScanGallerySource {
  ImagePickerScanGallery(this._picker, {bool? isAndroid})
    : _isAndroid = isAndroid ?? Platform.isAndroid;

  final ImagePicker _picker;
  final bool _isAndroid;

  @override
  Future<String?> selectImagePath() async {
    try {
      if (_isAndroid) {
        final recovered = await _picker.retrieveLostData();
        final exception = recovered.exception;
        if (exception != null) {
          throw ScanDriverException(
            code: 'scan_gallery_recovery_failed',
            kind: _galleryFailureKind(exception.code),
            diagnostic: FailureMapper.diagnosticCause(exception),
            stackTrace: StackTrace.current,
          );
        }
        final recoveredFile = recovered.file;
        if (!recovered.isEmpty && recoveredFile != null) {
          return recoveredFile.path;
        }
      }
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      return image?.path;
    } on ScanDriverException {
      rethrow;
    } on PlatformException catch (error, stackTrace) {
      throw ScanDriverException(
        code: 'scan_gallery_selection_failed',
        kind: _galleryFailureKind(error.code),
        diagnostic: FailureMapper.diagnosticCause(error),
        stackTrace: stackTrace,
      );
    } on UnsupportedError catch (error, stackTrace) {
      throw ScanDriverException(
        code: 'scan_gallery_unsupported',
        kind: ScanDriverFailureKind.unsupported,
        diagnostic: FailureMapper.diagnosticCause(error),
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      throw ScanDriverException(
        code: 'scan_gallery_selection_failed',
        kind: ScanDriverFailureKind.unavailable,
        diagnostic: FailureMapper.diagnosticCause(error),
        stackTrace: stackTrace,
      );
    }
  }

  static ScanDriverFailureKind _galleryFailureKind(String code) {
    final normalized = code.toLowerCase();
    if (normalized.contains('permission') || normalized.contains('access')) {
      return ScanDriverFailureKind.permissionDenied;
    }
    return ScanDriverFailureKind.unavailable;
  }
}

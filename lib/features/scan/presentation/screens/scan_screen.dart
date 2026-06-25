import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../shared/shared.dart';
import '../../../skeleton/presentation/providers/skeleton_index_provider.dart';
import '../view_model/view_model.dart';
import '../widgets/widgets.dart';

/// Scan screen with full-screen camera and QR/barcode scanning frame.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

/// Fixed zoom options: 1x, 2x, 3x (filtered by device min/max).
const List<double> _kZoomOptions = [1.0, 2.0, 3.0];

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _imagePicker = ImagePicker();
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 250,
  );

  /// Zoom factors: subset of [1x, 2x, 3x] within device min–max.
  List<double> _zoomFactors = [1.0];
  int _currentZoomIndex = 0;

  /// Build zoom options from [1x, 2x, 3x] that fall within device min/max.
  static List<double> _buildZoomFactors(double minZoom, double maxZoom) {
    if (maxZoom <= minZoom) return [minZoom];
    final factors = _kZoomOptions
        .where((f) => f >= minZoom && f <= maxZoom)
        .toList();
    if (factors.isEmpty) return [minZoom];
    return factors;
  }

  static String _formatZoomFactor(double factor) {
    if (factor == factor.roundToDouble()) {
      return '${factor.toInt()}x';
    }
    return '${factor.toStringAsFixed(1)}x';
  }

  Future<void> _pickImageAndScan(BuildContext context) async {
    final xFile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;
    try {
      final capture = await _scannerController.analyzeImage(xFile.path);
      if (!context.mounted) return;
      for (final barcode in capture?.barcodes ?? <Barcode>[]) {
        final raw = barcode.rawValue;
        if (raw != null && raw.isNotEmpty) {
          context.pop(raw);
          return;
        }
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No barcode found')));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to scan image')));
      }
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skeletonIndex = ref.watch(skeletonIndexProvider);
    final isScanTabActive = skeletonIndex == skeletonScanTabIndex;
    // When opened via push (e.g. from send address app bar), current route is /scan.
    final isPushedScanRoute =
        GoRouterState.of(context).matchedLocation == RoutePaths.scan;
    final shouldShowCamera = isScanTabActive || isPushedScanRoute;
    final scanState = ref.watch(scanViewModelProvider);
    final viewModel = ref.read(scanViewModelProvider.notifier);

    // When leaving the scan tab, reset flash and zoom so icons match actual state
    // (camera is stopped when tab is inactive, so flash is off and zoom is reset).
    ref.listen<int>(skeletonIndexProvider, (previous, next) {
      if (previous == skeletonScanTabIndex && next != skeletonScanTabIndex) {
        viewModel.setFlash(false);
        if (mounted) {
          setState(() => _currentZoomIndex = 0);
        }
      }
    });
    final spacing = context.spacing;
    final colors = context.appColors;
    final metrics = context.metrics;
    final frameSize =
        MediaQuery.sizeOf(context).width * metrics.scanFrameSizeFactor;
    final screenSize = MediaQuery.sizeOf(context);

    final headerHeight =
        spacing.xxxl +
        spacing.giant +
        spacing.md +
        spacing.md +
        spacing.sm +
        spacing.md +
        spacing.xxxl;
    final safeAreaTop = spacing.topSafeRaw(context);
    final frameTop = safeAreaTop + headerHeight;
    final frameLeft = (MediaQuery.sizeOf(context).width - frameSize) / 2;

    final cutoutRect = Rect.fromLTWH(frameLeft, frameTop, frameSize, frameSize);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: colors.transparentSurface,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: colors.transparentSurface,
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: shouldShowCamera
                      ? ScanCameraWidget(
                          controller: _scannerController,
                          cutoutRect: cutoutRect,
                          screenSize: screenSize,
                          flashOn: scanState.flashOn,
                          zoomFactor: _zoomFactors.isNotEmpty
                              ? _zoomFactors[_currentZoomIndex]
                              : 1.0,
                          onScanned: (value) {
                            context.pop(value);
                          },
                          onPermissionDenied: () {
                            viewModel.setPermissionDenied(true);
                          },
                          onError: (message) {
                            viewModel.setError(message);
                          },
                          onCameraReady: (minZoom, maxZoom) {
                            if (mounted) {
                              setState(() {
                                _zoomFactors = _buildZoomFactors(
                                  minZoom,
                                  maxZoom,
                                );
                                _currentZoomIndex = 0;
                              });
                            }
                          },
                        )
                      : SizedBox.shrink(),
                ),
                Positioned.fill(child: ScanBackground(cutoutRect: cutoutRect)),
                Column(
                  children: [
                    SizedBox(height: spacing.topSafeRaw(context)),
                    const ScanWalletHeader(
                      walletName: 'Wallet 1',
                      walletId: 'HD8H90 PX0S',
                    ),
                    SizedBox(height: spacing.xxxl),
                    ScanFrame(
                      zoomDisplayText: _formatZoomFactor(
                        _zoomFactors.isNotEmpty
                            ? _zoomFactors[_currentZoomIndex]
                            : 1.0,
                      ),
                      onFlashTap: () => viewModel.toggleFlash(),
                      onZoomTap: () {
                        if (_zoomFactors.isEmpty) return;
                        setState(() {
                          _currentZoomIndex =
                              (_currentZoomIndex + 1) % _zoomFactors.length;
                        });
                      },
                      onGalleryTap: () => _pickImageAndScan(context),
                    ),
                    const Spacer(),
                    ScanEnterAddressButton(onTap: () => context.pop()),
                    SizedBox(
                      height:
                          spacing.bottomSafe(context) +
                          metrics.floatingNavClearance +
                          spacing.xxl,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

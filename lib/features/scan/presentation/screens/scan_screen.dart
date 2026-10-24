import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../send/presentation/view_model/view_models.dart';
import '../../../shell/presentation/providers/app_shell_index_provider.dart';
import '../../domain/models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Full-screen payment QR scanner with an explicit completion contract.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, this.purpose = ScanPurpose.sendLauncher});

  final ScanPurpose purpose;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _navigationInFlight = false;

  Future<void> _handleCameraPayload(ScanPayload payload) async {
    final viewModel = ref.read(scanViewModelProvider(widget.purpose).notifier);
    if (!viewModel.acceptCameraPayload(payload)) return;
    await _completePayload(payload);
  }

  Future<void> _scanGallery() async {
    final toasts = context.toasts;
    final viewModel = ref.read(scanViewModelProvider(widget.purpose).notifier);
    final result = await viewModel.scanGallery();
    if (!mounted) return;
    switch (result) {
      case AppSuccess<ScanGalleryOutcome>(:final value):
        switch (value) {
          case ScanGalleryCaptured(:final payload):
            await _completePayload(payload);
          case ScanGalleryNoCode():
            toasts.show(
              title: 'No QR code found',
              message: 'Choose another image and try again.',
              variant: ToastVariant.warning,
            );
          case ScanGalleryCancelled():
            return;
        }
      case AppFailureResult<ScanGalleryOutcome>(:final failure):
        if (failure.code == 'scan_operation_unavailable') return;
        toasts.show(
          title: failure.kind == AppFailureKind.unsupported
              ? 'Image scanning unavailable'
              : 'Image could not be scanned',
          message: failure.userMessage,
          variant:
              failure.kind == AppFailureKind.unsupported ||
                  failure.kind == AppFailureKind.authentication
              ? ToastVariant.warning
              : ToastVariant.failure,
        );
    }
  }

  Future<void> _toggleFlash() async {
    final toasts = context.toasts;
    final result = await ref
        .read(scanViewModelProvider(widget.purpose).notifier)
        .toggleFlash();
    if (!mounted || result is AppSuccess<void>) return;
    _showControlFailure(
      title: 'Flashlight unavailable',
      failure: (result as AppFailureResult<void>).failure,
      toasts: toasts,
    );
  }

  Future<void> _cycleZoom() async {
    final toasts = context.toasts;
    final result = await ref
        .read(scanViewModelProvider(widget.purpose).notifier)
        .cycleZoom();
    if (!mounted || result is AppSuccess<void>) return;
    _showControlFailure(
      title: 'Zoom unavailable',
      failure: (result as AppFailureResult<void>).failure,
      toasts: toasts,
    );
  }

  void _showControlFailure({
    required String title,
    required AppFailure failure,
    required ToastPresentationService toasts,
  }) {
    if (failure.code == 'scan_operation_unavailable') return;
    toasts.show(
      title: title,
      message: failure.userMessage,
      variant:
          failure.kind == AppFailureKind.unsupported ||
              failure.kind == AppFailureKind.authentication
          ? ToastVariant.warning
          : ToastVariant.failure,
    );
  }

  Future<void> _completePayload(ScanPayload payload) async {
    if (_navigationInFlight) return;
    if (widget.purpose == ScanPurpose.destinationPicker) {
      if (context.canPop()) {
        context.pop(payload.value);
      } else {
        await _reportMissingPickerCaller();
      }
      return;
    }
    final staged = ref
        .read(sendDestinationHandoffProvider.notifier)
        .stage(payload.value);
    if (staged case AppFailureResult<void>(:final failure)) {
      context.toasts.show(
        title: 'Code could not be used',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
      await ref
          .read(scanViewModelProvider(widget.purpose).notifier)
          .resumeAfterNavigation();
      return;
    }
    await _openSend();
  }

  Future<void> _enterManually() async {
    if (_navigationInFlight) return;
    unawaited(context.haptics.trigger(HapticIntent.lightImpact));
    if (widget.purpose == ScanPurpose.destinationPicker) {
      if (context.canPop()) {
        context.pop<void>();
      } else {
        await _reportMissingPickerCaller();
      }
      return;
    }
    ref.read(sendDestinationHandoffProvider.notifier).clear();
    await _openSend();
  }

  Future<void> _reportMissingPickerCaller() async {
    context.toasts.show(
      title: 'Scan session expired',
      message: 'Return to Send and open the scanner again.',
      variant: ToastVariant.failure,
    );
    await ref
        .read(scanViewModelProvider(widget.purpose).notifier)
        .resumeAfterNavigation();
  }

  Future<void> _openSend() async {
    if (_navigationInFlight) return;
    final toasts = context.toasts;
    setState(() => _navigationInFlight = true);
    final viewModel = ref.read(scanViewModelProvider(widget.purpose).notifier);
    final destinationHandoff = ref.read(
      sendDestinationHandoffProvider.notifier,
    );
    final paused = await viewModel.pauseForNavigation();
    if (!mounted) {
      destinationHandoff.clear();
      return;
    }
    if (paused case AppFailureResult<void>(:final failure)) {
      destinationHandoff.clear();
      setState(() => _navigationInFlight = false);
      toasts.show(
        title: 'Scanner could not pause',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
      return;
    }
    try {
      await context.pushNamed<void>(RouteNames.send);
    } catch (error, stackTrace) {
      final failure = FailureMapper.from(error, stackTrace);
      destinationHandoff.clear();
      if (mounted) {
        unawaited(context.haptics.trigger(HapticIntent.error));
        toasts.show(
          title: 'Send could not be opened',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
      }
    } finally {
      if (mounted) {
        await viewModel.resumeAfterNavigation();
        if (mounted) setState(() => _navigationInFlight = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanViewModelProvider(widget.purpose));
    final viewModel = ref.read(scanViewModelProvider(widget.purpose).notifier);
    final shellIndex = ref.watch(appShellIndexProvider);
    final shouldShowCamera =
        widget.purpose == ScanPurpose.destinationPicker ||
        shellIndex == appShellScanTabIndex;
    final walletIdentity = ref.watch(scanWalletIdentityViewModelProvider);
    final activeWallet = walletIdentity.value;
    final walletFailure = switch (walletIdentity) {
      AsyncError(:final error, :final stackTrace) =>
        error is AppFailureException
            ? error.failure
            : FailureMapper.from(error, stackTrace),
      _ => null,
    };
    final spacing = context.spacing;
    final colors = context.appColors;
    final metrics = context.metrics;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: colors.transparentSurface,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: colors.scanOverlayBase,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final safeTop = context.windowInsets.topSystem;
            final persistentNavClearance =
                widget.purpose == ScanPurpose.sendLauncher
                ? metrics.floatingNavClearance + spacing.xxl
                : spacing.xxl;
            final ctaBottom =
                context.windowInsets.bottomSystem + persistentNavClearance;
            final frameTop = safeTop + metrics.scanHeaderExtent;
            final footerExtent =
                metrics.minTouchTarget + spacing.xl + ctaBottom;
            final availableFrameHeight = math.max(
              0.0,
              constraints.maxHeight - frameTop - footerExtent,
            );
            final widthBasedSize =
                constraints.maxWidth * metrics.scanFrameSizeFactor;
            final frameSize = math.min(
              metrics.scanFrameMaximumSize,
              math.min(widthBasedSize, availableFrameHeight),
            );
            final frameLeft = (constraints.maxWidth - frameSize) / 2;
            final cutoutRect = Rect.fromLTWH(
              frameLeft,
              frameTop,
              frameSize,
              frameSize,
            );

            return FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: shouldShowCamera
                        ? ScanCamera(
                            purpose: widget.purpose,
                            cutoutRect: cutoutRect,
                            placeholderColor: colors.scanOverlayBase,
                            onCaptured: (payload) =>
                                unawaited(_handleCameraPayload(payload)),
                          )
                        : ColoredBox(color: colors.scanOverlayBase),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ScanBackground(cutoutRect: cutoutRect),
                    ),
                  ),
                  Positioned(
                    top: safeTop,
                    left: spacing.screenPadding,
                    right: spacing.screenPadding,
                    height: metrics.scanHeaderExtent,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(0),
                      child: ScanWalletHeader(
                        walletName: activeWallet?.name,
                        walletId: activeWallet?.displayId,
                        loading: walletIdentity.isLoading,
                        failureMessage: walletFailure?.userMessage,
                        onRetry:
                            !walletIdentity.isLoading &&
                                walletFailure?.retryable == true
                            ? () => unawaited(
                                ref
                                    .read(
                                      scanWalletIdentityViewModelProvider
                                          .notifier,
                                    )
                                    .retry(),
                              )
                            : null,
                      ),
                    ),
                  ),
                  Positioned(
                    top: frameTop,
                    left: frameLeft,
                    child: ScanFrame(
                      size: frameSize,
                      state: scanState,
                      onGalleryTap: scanState.canUseGallery && shouldShowCamera
                          ? () => unawaited(_scanGallery())
                          : null,
                      onFlashTap: scanState.canToggleFlash
                          ? () => unawaited(_toggleFlash())
                          : null,
                      onZoomTap: scanState.canChangeZoom
                          ? () => unawaited(_cycleZoom())
                          : null,
                      onRetry: scanState.canRetry
                          ? () => unawaited(viewModel.retryCamera())
                          : null,
                    ),
                  ),
                  Positioned(
                    left: spacing.screenPadding,
                    right: spacing.screenPadding,
                    bottom: ctaBottom,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(4),
                      child: ScanEnterAddressButton(
                        label: widget.purpose == ScanPurpose.destinationPicker
                            ? 'Enter payment details manually'
                            : 'Enter payment details to send',
                        onTap:
                            !scanState.canEnterManually ||
                                _navigationInFlight ||
                                !shouldShowCamera
                            ? null
                            : () => unawaited(_enterManually()),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

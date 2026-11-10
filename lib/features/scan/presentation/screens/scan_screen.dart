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
  bool get _bridge => widget.purpose == ScanPurpose.bridgePairing;

  bool get _isCurrentSurface =>
      mounted &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      (ModalRoute.of(context)?.isCurrent ?? false) &&
      (widget.purpose != ScanPurpose.sendLauncher ||
          ref.read(appShellIndexProvider) == appShellScanTabIndex);

  Future<void> _handleCameraPayload(ScanPayload payload) async {
    final viewModel = ref.read(scanViewModelProvider(widget.purpose).notifier);
    if (!viewModel.acceptCameraPayload(payload)) return;
    await _completePayload(payload);
  }

  Future<void> _scanGallery() async {
    final toasts = context.toasts;
    final viewModel = ref.read(scanViewModelProvider(widget.purpose).notifier);
    final result = await viewModel.scanGallery();
    if (!_isCurrentSurface) {
      // Release a gallery capture even when its caller has since been covered.
      // Native attachment/lifecycle still gates any actual camera start.
      await viewModel.resumeAfterNavigation();
      return;
    }
    switch (result) {
      case AppSuccess<ScanGalleryOutcome>(:final value):
        switch (value) {
          case ScanGalleryCaptured(:final payload):
            await _completePayload(payload);
          case ScanGalleryNoCode():
            toasts.show(
              title: _bridge ? 'No connection QR found' : 'No payment QR found',
              message: _bridge
                  ? 'Choose an image with a Dev Bridge connection QR.'
                  : 'Choose an image with a valid Bitcoin or USDT payment QR.',
              variant: ToastVariant.warning,
            );
          case ScanGalleryCancelled():
            return;
        }
      case AppFailureResult<ScanGalleryOutcome>(:final failure):
        if (failure.code == 'scan_operation_unavailable') return;
        toasts.show(
          title: switch (failure.kind) {
            AppFailureKind.authentication => 'Photo access unavailable',
            AppFailureKind.unsupported => 'Image scanning unavailable',
            _ => 'Image could not be scanned',
          },
          message: switch (failure.kind) {
            AppFailureKind.authentication =>
              'Allow photo access in system settings, or scan with the camera.',
            AppFailureKind.unsupported =>
              'Use the camera or enter the payment details manually.',
            _ =>
              'A valid payment QR could not be read. Choose a clearer image.',
          },
          variant: ToastVariant.warning,
        );
    }
  }

  Future<void> _toggleFlash() async {
    await ref
        .read(scanViewModelProvider(widget.purpose).notifier)
        .toggleFlash();
  }

  Future<void> _cycleZoom() async {
    await ref.read(scanViewModelProvider(widget.purpose).notifier).cycleZoom();
  }

  Future<void> _completePayload(ScanPayload payload) async {
    if (!_isCurrentSurface) {
      await ref
          .read(scanViewModelProvider(widget.purpose).notifier)
          .resumeAfterNavigation();
      return;
    }
    if (_navigationInFlight) return;
    if (widget.purpose != ScanPurpose.sendLauncher) {
      if (context.canPop()) {
        context.pop(payload.value);
        return;
      }
      if (_bridge) return;
      // A directly opened picker has no caller to return to. Complete through
      // the normal Send launcher; the camera itself never expires.
    }
    final staged = ref
        .read(sendDestinationHandoffProvider.notifier)
        .stage(payload.value);
    if (staged is AppFailureResult<void>) {
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
    if (widget.purpose != ScanPurpose.sendLauncher) {
      if (context.canPop()) {
        context.pop<void>();
        return;
      }
      if (_bridge) return;
    }
    ref.read(sendDestinationHandoffProvider.notifier).clear();
    await _openSend();
  }

  Future<void> _openSend() async {
    if (_navigationInFlight) return;
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
    if (!_isCurrentSurface ||
        !viewModel.navigationContextCurrent ||
        paused is AppFailureResult<void>) {
      destinationHandoff.clear();
      await viewModel.resumeAfterNavigation();
      if (mounted) setState(() => _navigationInFlight = false);
      return;
    }
    try {
      await context.pushNamed<void>(RouteNames.send);
    } catch (error, stackTrace) {
      destinationHandoff.clear();
      viewModel.navigationFailed(error, stackTrace);
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
    final shellIndex = ref.watch(appShellIndexProvider);
    final shouldShowCamera =
        (ModalRoute.of(context)?.isCurrent ?? false) &&
        (widget.purpose != ScanPurpose.sendLauncher ||
            shellIndex == appShellScanTabIndex);
    final walletIdentity = ref.watch(scanWalletIdentityViewModelProvider);
    final activeWallet = walletIdentity.isLoading || walletIdentity.hasError
        ? null
        : walletIdentity.value;
    final spacing = context.spacing;
    final colors = context.appColors;
    final metrics = context.metrics;
    final isDuoCover =
        ref
            .watch(duoCoverLayoutProvider)
            .value
            ?.appliesTo(MediaQuery.sizeOf(context)) ==
        true;
    final usesCompactBottom = isDuoCover || context.isOpenDuoLandscape;
    final manualEntryLabel = _bridge
        ? 'Enter connection link manually'
        : widget.purpose == ScanPurpose.destinationPicker
        ? 'Enter payment details manually'
        : 'Enter payment details to send';

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
            final insets = context.windowInsets.systemPadding;
            final safeWidth = math.max(
              0.0,
              constraints.maxWidth - insets.horizontal,
            );
            final controlsLeft = insets.left + spacing.screenPadding;
            final controlsRight = insets.right + spacing.screenPadding;
            final persistentNavClearance =
                widget.purpose == ScanPurpose.sendLauncher &&
                    (!usesCompactBottom ||
                        CoverTabRail.hasBottomFallbackOf(context))
                ? metrics.floatingNavClearance
                : 0.0;
            final actionMargin = usesCompactBottom ? spacing.lg : spacing.xxl;
            final ctaBottom =
                insets.bottom + persistentNavClearance + actionMargin;
            final frameTop = insets.top + metrics.scanHeaderExtent;
            final ctaHeight = ScanEnterAddressButton.heightForWidth(
              context,
              label: manualEntryLabel,
              width: safeWidth - spacing.screenPadding * 2,
            );
            final footerExtent = ctaHeight + spacing.xl + ctaBottom;
            final availableFrameHeight = math.max(
              0.0,
              constraints.maxHeight - frameTop - footerExtent,
            );
            final widthBasedSize = safeWidth * metrics.scanFrameSizeFactor;
            final frameSize = math.min(
              metrics.scanFrameMaximumSize,
              math.min(widthBasedSize, availableFrameHeight),
            );
            // The camera and overlay remain edge to edge. Keep their shared
            // window in that coordinate space while centering the frame inside
            // the safe content area.
            final frameLeft = insets.left + (safeWidth - frameSize) / 2;
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
                    top: insets.top,
                    left: controlsLeft,
                    right: controlsRight,
                    height: metrics.scanHeaderExtent,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(0),
                      child: ScanWalletHeader(
                        walletName: activeWallet?.name,
                        walletId: activeWallet?.displayId,
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
                    ),
                  ),
                  Positioned(
                    left: controlsLeft,
                    right: controlsRight,
                    bottom: ctaBottom,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(4),
                      child: ScanEnterAddressButton(
                        label: manualEntryLabel,
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

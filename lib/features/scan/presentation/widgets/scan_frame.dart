import 'package:flutter/material.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';
import '../models/models.dart';
import 'scan_control_button.dart';

/// Camera focus frame, persistent status, and capability-aware controls.
class ScanFrame extends StatelessWidget {
  const ScanFrame({
    super.key,
    required this.size,
    required this.state,
    required this.onGalleryTap,
    required this.onFlashTap,
    required this.onZoomTap,
    required this.onRetry,
  });

  final double size;
  final ScanState state;
  final VoidCallback? onGalleryTap;
  final VoidCallback? onFlashTap;
  final VoidCallback? onZoomTap;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final effects = context.effects;
    final icons = context.icons;
    final metrics = context.metrics;
    final strokes = context.strokes;
    final controlClearance = metrics.minTouchTarget + spacing.xl;
    final status = switch (state.failure) {
      final failure? => SingleChildScrollView(
        primary: false,
        padding: EdgeInsets.symmetric(vertical: spacing.sm),
        child: _ScanFailureStatus(failure: failure, onRetry: onRetry),
      ),
      null when !state.cameraReady => Semantics(
        liveRegion: true,
        label: 'Starting camera',
        child: GridLoader(
          colorStyle: GridLoaderColorStyle.custom,
          color: colors.onScan,
        ),
      ),
      null => const SizedBox.shrink(),
    };

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.onScan, width: strokes.hairline),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              bottom: controlClearance,
              child: Center(child: status),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: spacing.md),
                child: AsterPill(
                  padding: EdgeInsets.all(spacing.xs),
                  color: colors.scanControlSurface.withValues(
                    alpha: effects.scanControlSurfaceOpacity,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: ScanControlButton(
                          semanticLabel: 'Choose a QR image',
                          loading: state.galleryBusy,
                          onTap: onGalleryTap,
                          child: Icon(
                            MingCuteIcons.mgc_photo_album_line,
                            color: colors.onScan,
                            size: icons.xs,
                          ),
                        ),
                      ),
                      SizedBox(width: spacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: ScanControlButton(
                          semanticLabel: state.flashOn
                              ? 'Turn flashlight off'
                              : 'Turn flashlight on',
                          selected: state.flashOn,
                          onTap: onFlashTap,
                          child: Icon(
                            state.flashOn
                                ? MingCuteIcons.mgc_flash_fill
                                : MingCuteIcons.mgc_flash_line,
                            color: colors.onScan,
                            size: icons.xs,
                          ),
                        ),
                      ),
                      SizedBox(width: spacing.sm),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(3),
                        child: ScanControlButton(
                          semanticLabel: 'Change zoom level',
                          value: state.zoomPreset.semanticLabel,
                          onTap: onZoomTap,
                          child: NumericText(
                            state.zoomPreset.displayLabel,
                            style: context.type.scanControl,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanFailureStatus extends StatelessWidget {
  const _ScanFailureStatus({required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              failure.userMessage,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.appColors.onScan,
              ),
              textAlign: TextAlign.center,
            ),
            if (failure.retryable && onRetry != null) ...[
              SizedBox(height: context.spacing.md),
              CustomButton.compact(
                text: 'Retry',
                hapticIntent: null,
                onTap: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

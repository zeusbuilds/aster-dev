import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../models/models.dart';
import 'scan_control_button.dart';

/// Quiet camera focus frame and capability-aware controls.
class ScanFrame extends StatelessWidget {
  const ScanFrame({
    super.key,
    required this.size,
    required this.state,
    required this.onGalleryTap,
    required this.onFlashTap,
    required this.onZoomTap,
  });

  final double size;
  final ScanState state;
  final VoidCallback? onGalleryTap;
  final VoidCallback? onFlashTap;
  final VoidCallback? onZoomTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final effects = context.effects;
    final strokes = context.strokes;
    final controlGlyphSize = context.icons.scanControlGlyph;
    final zoom = state.zoom;
    final zoomLabel = zoom?.displayLabel;
    final zoomStyle = context.type.scanControl;
    final zoomText = TextPainter(
      text: TextSpan(
        style: zoomStyle,
        children: NumericTextSpans.build(context, zoomLabel ?? '', zoomStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    // All circles grow together for large text or fractional magnification.
    // Keep the entire pill inside the frame, including the hit-cell inset
    // around each circle; only scale a label down after reaching that cap.
    final controlDiameter = math.min(
      math.max(32.0, size / 3 - spacing.sm),
      math.max(32.0, math.max(zoomText.width, zoomText.height) + spacing.sm),
    );
    zoomText.dispose();

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.onScan, width: strokes.hairline),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: spacing.md),
                child: AsterPill(
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
                          contentDiameter: controlDiameter,
                          busy: state.galleryBusy,
                          onTap: onGalleryTap,
                          child: Icon(
                            MingCuteIcons.mgc_photo_album_line,
                            color: colors.onScan,
                            size: controlGlyphSize,
                          ),
                        ),
                      ),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: ScanControlButton(
                          semanticLabel: state.flashOn
                              ? 'Turn flashlight off'
                              : 'Turn flashlight on',
                          selected: state.flashOn,
                          contentDiameter: controlDiameter,
                          onTap: onFlashTap,
                          child: Icon(
                            state.flashOn
                                ? MingCuteIcons.mgc_flash_fill
                                : MingCuteIcons.mgc_flash_line,
                            color: colors.onScan,
                            size: controlGlyphSize,
                          ),
                        ),
                      ),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(3),
                        child: ScanControlButton(
                          semanticLabel: 'Change zoom level',
                          value: zoom?.semanticLabel,
                          contentDiameter: controlDiameter,
                          busy: state.operation == ScanOperation.changingZoom,
                          onTap: onZoomTap,
                          child: zoomLabel == null
                              ? Icon(
                                  Icons.zoom_in,
                                  color: colors.onScan,
                                  size: controlGlyphSize,
                                )
                              : Padding(
                                  padding: EdgeInsets.all(spacing.xs),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: NumericText(
                                      zoomLabel,
                                      style: zoomStyle,
                                      maxLines: 1,
                                    ),
                                  ),
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

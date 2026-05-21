import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../view_model/view_model.dart';
import 'scan_control_button.dart';

/// QR code scanning frame with control buttons (gallery, flash, zoom).
class ScanFrame extends ConsumerWidget {
  const ScanFrame({
    super.key,
    this.zoomDisplayText = '1x',
    this.onGalleryTap,
    this.onFlashTap,
    this.onZoomTap,
  });

  final String zoomDisplayText;
  final VoidCallback? onGalleryTap;
  final VoidCallback? onFlashTap;
  final VoidCallback? onZoomTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flashOn = ref.watch(scanViewModelProvider).flashOn;
    final spacing = context.spacing;
    final colors = context.appColors;
    final effects = context.effects;
    final metrics = context.metrics;
    final radius = context.radii;
    final textTheme = context.textTheme;
    final frameSize =
        MediaQuery.of(context).size.width * metrics.scanFrameSizeFactor;

    return Container(
      width: frameSize,
      height: frameSize,
      padding: EdgeInsets.only(bottom: spacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: colors.onScan, width: spacing.hairline),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: EdgeInsets.all(spacing.xs),
          decoration: BoxDecoration(
            color: colors.scanControlSurface.withValues(
              alpha: effects.scanControlSurfaceOpacity,
            ),
            borderRadius: BorderRadius.circular(radius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScanControlButton(
                onTap: onGalleryTap ?? () {},
                child: Icon(
                  MingCuteIcons.mgc_photo_album_line,
                  color: colors.onScan,
                  size: spacing.lg,
                ),
              ),
              SizedBox(width: spacing.sm),
              ScanControlButton(
                onTap: onFlashTap ?? () {},
                child: Icon(
                  flashOn
                      ? MingCuteIcons.mgc_flash_fill
                      : MingCuteIcons.mgc_flash_line,
                  color: colors.onScan,
                  size: spacing.lg,
                ),
              ),
              SizedBox(width: spacing.sm),
              ScanControlButton(
                onTap: onZoomTap ?? () {},
                child: Text(
                  zoomDisplayText,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onScan,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

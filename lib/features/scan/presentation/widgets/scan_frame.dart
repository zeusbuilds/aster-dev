import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aster/shared/shared.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import 'package:aster/features/scan/presentation/view_model/view_model.dart';
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
    final colors = context.colors;
    final radius = context.radius;
    final textTheme = context.textTheme;
    final frameSize = MediaQuery.of(context).size.width * 0.7;

    return Container(
      width: frameSize,
      height: frameSize,
      padding: EdgeInsets.only(bottom: spacing.spacing14),
      decoration: BoxDecoration(
        border: Border.all(color: colors.text5, width: 0.5),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: EdgeInsets.all(spacing.spacing4),
          decoration: BoxDecoration(
            color: colors.fill6.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(radius.radius50),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScanControlButton(
                onTap: onGalleryTap ?? () {},
                child: Icon(
                  MingCuteIcons.mgc_photo_album_line,
                  color: colors.text5,
                  size: spacing.spacing16,
                ),
              ),
              SizedBox(width: spacing.spacing8),
              ScanControlButton(
                onTap: onFlashTap ?? () {},
                child: Icon(
                  flashOn
                      ? MingCuteIcons.mgc_flash_fill
                      : MingCuteIcons.mgc_flash_line,
                  color: colors.text5,
                  size: spacing.spacing16,
                ),
              ),
              SizedBox(width: spacing.spacing8),
              ScanControlButton(
                onTap: onZoomTap ?? () {},
                child: Text(
                  zoomDisplayText,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.text5,
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

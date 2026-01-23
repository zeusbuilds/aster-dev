import 'package:flutter/material.dart';

import 'package:aster/shared/shared.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import 'scan_control_button.dart';

/// QR code scanning frame with control buttons
class ScanFrame extends StatelessWidget {
  const ScanFrame({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;
    final radius = context.radius;
    final frameSize = MediaQuery.of(context).size.width * 0.7;

    return Stack(
      children: [
        // Clear background inside the frame (cuts through gradient/blur)
        Container(
          width: frameSize,
          height: frameSize,
          color: Colors.transparent,
        ),
        // Frame border and controls
        Container(
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
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(radius.radius50),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScanControlButton(
                    icon: MingCuteIcons.mgc_photo_album_line,
                    onTap: () {
                      // TODO: Handle gallery tap
                    },
                  ),
                  SizedBox(width: spacing.spacing8),
                  ScanControlButton(
                    icon: MingCuteIcons.mgc_flash_line,
                    onTap: () {
                      // TODO: Handle flash tap
                    },
                  ),
                  SizedBox(width: spacing.spacing8),
                  ScanControlButton(
                    icon: MingCuteIcons.mgc_zoom_in_line,
                    onTap: () {
                      // TODO: Handle zoom tap
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

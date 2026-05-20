import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import 'scan_overlay_painter.dart';

/// Background widget for scan screen with gradient overlay with cutout.
class ScanBackground extends StatelessWidget {
  final Rect cutoutRect;

  const ScanBackground({super.key, required this.cutoutRect});

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      colors: [
        AsterColors.black,
        AsterColors.black.withValues(alpha: 0.75),
        AsterColors.black.withValues(alpha: 0.65),
      ],
      stops: const [0.25, 0.5, 1.0],
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
    );

    return CustomPaint(
      painter: ScanOverlayPainter(cutoutRect: cutoutRect, gradient: gradient),
      size: Size.infinite,
    );
  }
}

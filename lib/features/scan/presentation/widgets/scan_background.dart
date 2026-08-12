import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import 'scan_overlay_painter.dart';

/// Token-owned Scan scrim that leaves the active camera window unobscured.
class ScanBackground extends StatelessWidget {
  final Rect cutoutRect;

  const ScanBackground({super.key, required this.cutoutRect});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ScanOverlayPainter(
        cutoutRect: cutoutRect,
        gradient: context.gradients.scanOverlay.toLinearGradient(),
      ),
      size: Size.infinite,
    );
  }
}

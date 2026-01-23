import 'package:flutter/material.dart';

import 'scan_overlay_painter.dart';

/// Background widget for scan screen with image, blur, and gradient overlay
class ScanBackground extends StatelessWidget {
  final Rect cutoutRect;

  const ScanBackground({super.key, required this.cutoutRect});

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      colors: [
        Colors.black,
        Colors.black.withValues(alpha: 0.75),
        Colors.black.withValues(alpha: 0.65),
      ],
      stops: const [0.25, 0.5, 1.0],
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
    );

    return Stack(
      children: [
        Image.asset(
          'assets/texture/scan-background.jpg',
          fit: BoxFit.cover,
          height: double.infinity,
          width: double.infinity,
        ),
        // Gradient overlay with optional cutout
        CustomPaint(
          painter: ScanOverlayPainter(
            cutoutRect: cutoutRect,
            gradient: gradient,
          ),
          size: Size.infinite,
        ),
      ],
    );
  }
}

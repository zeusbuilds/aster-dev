import 'package:flutter/material.dart';

/// Custom painter that draws gradient overlay with a cutout for the scan frame
class ScanOverlayPainter extends CustomPainter {
  final Rect cutoutRect;
  final LinearGradient gradient;

  ScanOverlayPainter({required this.cutoutRect, required this.gradient});

  @override
  void paint(Canvas canvas, Size size) {
    // Create a path for the entire screen
    final fullPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Create a path for the cutout area
    final cutoutPath = Path()..addRect(cutoutRect);

    // Use PathOperation.difference to create a hole
    final path = Path.combine(PathOperation.difference, fullPath, cutoutPath);

    // Draw the gradient overlay with the cutout
    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ScanOverlayPainter oldDelegate) {
    return oldDelegate.cutoutRect != cutoutRect ||
        oldDelegate.gradient != gradient;
  }
}

import 'package:flutter/material.dart';

/// Paints the token-owned camera scrim outside the active scan window.
class ScanOverlayPainter extends CustomPainter {
  ScanOverlayPainter({required this.cutoutRect, required this.gradient});

  final Rect cutoutRect;
  final LinearGradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final fullPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addRect(cutoutRect);
    final path = Path.combine(PathOperation.difference, fullPath, cutoutPath);
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

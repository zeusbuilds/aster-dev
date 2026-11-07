import 'dart:ui';

/// The launch-only treatment of the canonical, united Aster mark.
///
/// Geometry, gradient and effects match the native Figma export in
/// test/fixtures/branding/aster-launch-figma.svg. Its effects
/// scale with the 705-unit visible mark, rather than using device-sized blurs.
abstract final class AsterLaunchLogo {
  static const _sourceWidth = 705.0;
  static const _gradientStops = <double>[0.346154, 1];
  static const _bottomOpacity = 0.3;
  static const _shadows = <_LaunchShadow>[
    _LaunchShadow(offset: Offset(0, 2), sigma: 3, opacity: 0.1),
    _LaunchShadow(offset: Offset(0, 10), sigma: 15, opacity: 0.06),
  ];
  static const _hardAlpha = ColorFilter.matrix(<double>[
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    127,
    0,
  ]);

  /// Draws the stationary opening appearance at 0 and the solid reveal mark at
  /// 1. The caller owns path geometry, placement and the animation timeline.
  ///
  /// [path] must already unite its strokes: independently painting overlapping
  /// translucent strokes would darken their intersections. [logoBounds] are
  /// the unshadowed mark's bounds, keeping the gradient fixed to the artwork.
  static void paint(
    Canvas canvas, {
    required Path path,
    required Rect logoBounds,
    required Color blueColor,
    required Color finalColor,
    required double colorProgress,
  }) {
    assert(colorProgress.isFinite);
    assert(logoBounds.isFinite);
    if (logoBounds.isEmpty) return;

    final progress = colorProgress.clamp(0.0, 1.0);
    if (progress == 1) {
      // The existing reveal has no effects or off-screen layers. In particular,
      // never leave a faint shadow underneath its expanding white strokes.
      canvas.drawPath(path, Paint()..color = finalColor);
      return;
    }

    final shadowVisibility = 1 - progress;
    final scale = logoBounds.width / _sourceWidth;
    // The export includes 30/30 horizontal and 20/40 vertical padding. Its
    // explicit filter extent clips the shadow; preserving that extent matters
    // when matching the first Flutter frame to the exported native artwork.
    final filterBounds = Rect.fromLTRB(
      logoBounds.left - 30 * scale,
      logoBounds.top - 20 * scale,
      logoBounds.right + 30 * scale,
      logoBounds.bottom + 40 * scale,
    );
    final sourcePaint = Paint()
      ..shader = _gradient(
        logoBounds,
        blueColor.withValues(alpha: 1),
        blueColor.withValues(alpha: _bottomOpacity),
      );
    canvas.save();
    canvas.clipRect(filterBounds);
    for (final shadow in _shadows) {
      final opacity = shadow.opacity * shadowVisibility;
      final sigma = shadow.sigma * scale;
      final offset = shadow.offset * scale;
      final layerBounds = logoBounds.shift(offset).inflate(sigma * 3 + 1);
      canvas.saveLayer(
        filterBounds,
        Paint()
          ..colorFilter = ColorFilter.mode(
            Color.fromRGBO(0, 0, 0, opacity),
            BlendMode.srcIn,
          ),
      );
      canvas.saveLayer(
        layerBounds,
        Paint()..imageFilter = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
      canvas.saveLayer(
        logoBounds.shift(offset).inflate(1),
        Paint()..colorFilter = _hardAlpha,
      );
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.drawPath(path, sourcePaint);
      canvas.restore();
      canvas.restore();
      canvas.restore();
      // Figma's `feComposite operator="out"` removes the hard source mask
      // before the shadow opacity is applied. Consequently the translucent
      // blue fill never has a dark shadow showing through its own interior.
      canvas.saveLayer(
        logoBounds,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..colorFilter = _hardAlpha,
      );
      canvas.drawPath(path, sourcePaint);
      canvas.restore();
      canvas.restore();
    }
    canvas.restore();

    // Interpolate the fill separately from the original hard-alpha shadow mask;
    // both outside shadows explicitly fade to zero as the fill becomes opaque.
    canvas.drawPath(
      path,
      Paint()
        ..shader = _gradient(
          logoBounds,
          Color.lerp(blueColor.withValues(alpha: 1), finalColor, progress)!,
          Color.lerp(
            blueColor.withValues(alpha: _bottomOpacity),
            finalColor,
            progress,
          )!,
        ),
    );
  }

  static Shader _gradient(Rect bounds, Color top, Color bottom) =>
      Gradient.linear(bounds.topCenter, bounds.bottomCenter, [
        top,
        bottom,
      ], _gradientStops);
}

final class _LaunchShadow {
  const _LaunchShadow({
    required this.offset,
    required this.sigma,
    required this.opacity,
  });

  final Offset offset;
  final double sigma;
  final double opacity;
}

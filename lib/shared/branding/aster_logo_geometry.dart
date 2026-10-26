import 'dart:math' as math;
import 'dart:ui';

/// The three strokes in assets/brand/aster-mark.svg, in its 705 × 373 viewBox.
///
/// Keep the exported vertices, including their slight asymmetry, rather than
/// approximating the diagonal strokes with 45-degree rectangles. The animation
/// can then separate and turn the strokes without changing the opening mark.
abstract final class AsterLogoGeometry {
  static const size = Size(705, 373);
  static const horizontal = Rect.fromLTRB(0, 166.366, 705, 206.944);

  static const _descending = <Offset>[
    Offset(194.165, 0),
    Offset(539.285, 344.308),
    Offset(510.526, 373),
    Offset(165.403, 28.6915),
  ];
  static const _ascending = <Offset>[
    Offset(165.403, 344.308),
    Offset(510.526, 0),
    Offset(539.285, 28.6915),
    Offset(194.163, 373),
  ];

  static double horizontalThicknessForWidth(double width) =>
      horizontal.height / size.width * width;

  /// The mark centred in display coordinates, with its original strokes at 0.
  ///
  /// [horizontalWidth] expands the middle stroke to the viewport. Each diagonal
  /// rotates around its own centre and gently aligns with the middle stroke as
  /// it closes. This retains the exported first frame and a level reveal line.
  static Path animatedPath({
    required double logoWidth,
    required double horizontalWidth,
    required double rotationProgress,
    required double expansionProgress,
    bool includeHorizontal = true,
    bool includeDiagonals = true,
  }) {
    final scale = logoWidth / size.width;
    final sourceCenter = size.center(Offset.zero);
    Path? combined;

    void addStroke(Path stroke) {
      combined = combined == null
          ? stroke
          : Path.combine(PathOperation.union, combined!, stroke);
    }

    if (includeHorizontal) {
      addStroke(
        Path()..addRect(
          Rect.fromCenter(
            center: Offset(
              0,
              (horizontal.center.dy - sourceCenter.dy) *
                  scale *
                  (1 - expansionProgress),
            ),
            width: horizontalWidth,
            height: horizontalThicknessForWidth(logoWidth),
          ),
        ),
      );
    }

    if (includeDiagonals) {
      for (final vertices in [_descending, _ascending]) {
        final center =
            vertices.reduce((a, b) => a + b) / vertices.length.toDouble();
        final axis =
            (vertices[1] + vertices[2] - vertices[0] - vertices[3]) / 2;
        final turn = -math.atan2(axis.dy, axis.dx) * rotationProgress;
        final cosine = math.cos(turn);
        final sine = math.sin(turn);
        final targetCenter = Offset(
          center.dx + (sourceCenter.dx - center.dx) * rotationProgress,
          center.dy + (horizontal.center.dy - center.dy) * rotationProgress,
        );
        addStroke(
          Path()..addPolygon([
            for (final vertex in vertices)
              Offset(
                        (vertex.dx - center.dx) * cosine -
                            (vertex.dy - center.dy) * sine,
                        (vertex.dx - center.dx) * sine +
                            (vertex.dy - center.dy) * cosine,
                      ) *
                      scale +
                  (targetCenter - sourceCenter) * scale,
          ], true),
        );
      }
    }

    return combined ?? Path();
  }
}

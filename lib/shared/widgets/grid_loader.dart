import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/theme.dart';

const int _gridLoaderRows = 3;
const int _gridLoaderColumns = 3;

/// Size presets for the 3×3 grid loader.
enum GridLoaderSize { small, medium, large }

double _squareSizeFor(GridLoaderSize size, AsterComponentMetrics metrics) {
  switch (size) {
    case GridLoaderSize.small:
      return metrics.gridLoaderSmallCell;
    case GridLoaderSize.medium:
      return metrics.gridLoaderMediumCell;
    case GridLoaderSize.large:
      return metrics.gridLoaderLargeCell;
  }
}

/// Animation patterns for the 3×3 grid loader.
///
/// - [breathingGrid]: all cells pulse with subtle phase offsets.
/// - [borderLoop]: a single active cell with a trailing tail moves around the
///   outer ring (center is always transparent).
/// - [plusLoop]: a single active cell with a trailing tail moves along a plus
///   shape (top / right / bottom / left only, center and corners transparent).
enum GridLoaderStyle { breathingGrid, borderLoop, plusLoop }

/// Color source for the grid loader.
enum GridLoaderColorStyle {
  /// Theme primary (brand) color
  themePrimary,

  /// White (e.g. on dark backgrounds)
  white,

  /// Custom color via [GridLoader.color]
  custom,
}

/// 3×3 grid loading indicator with multiple animation styles.
///
/// The widget is drawn with a single [CustomPainter] for performance and uses
/// only opacity animations (no scaling), so it stays pixel-perfect inside
/// tightly constrained layouts like buttons.
class GridLoader extends StatefulWidget {
  final GridLoaderStyle style;
  final GridLoaderColorStyle colorStyle;
  final GridLoaderSize size;

  /// Custom color when [colorStyle] is [GridLoaderColorStyle.custom].
  final Color? color;

  const GridLoader({
    super.key,
    this.style = GridLoaderStyle.breathingGrid,
    this.colorStyle = GridLoaderColorStyle.white,
    this.size = GridLoaderSize.small,
    this.color,
  });

  @override
  State<GridLoader> createState() => _GridLoaderState();
}

class _GridLoaderState extends State<GridLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _synchronizeAnimation();
  }

  @override
  void didUpdateWidget(GridLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronizeAnimation();
  }

  void _synchronizeAnimation() {
    final duration = context.motion.loadingCycleDuration;
    final durationChanged = _controller.duration != duration;
    _controller.duration = duration;
    if (context.motionPolicy.reduceMotion || duration <= Duration.zero) {
      _controller.stop();
      _controller.value = context.motion.settledLoopProgress;
      return;
    }
    if (durationChanged || !_controller.isAnimating) {
      _controller.stop();
      unawaited(_controller.repeat(period: duration));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = switch (widget.colorStyle) {
      GridLoaderColorStyle.themePrimary => context.colorScheme.primary,
      GridLoaderColorStyle.white => context.appColors.onBrandArt,
      GridLoaderColorStyle.custom =>
        widget.color ?? context.colorScheme.primary,
    };

    final squareSize = _squareSizeFor(widget.size, context.metrics);
    final gridWidth = _gridLoaderColumns * squareSize;
    final gridHeight = _gridLoaderRows * squareSize;
    final effects = context.effects;

    return SizedBox(
      width: gridWidth,
      height: gridHeight,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size(gridWidth, gridHeight),
            painter: _GridLoaderPainter(
              progress: _controller.value,
              style: widget.style,
              squareSize: squareSize,
              color: baseColor,
              breathingMinimumOpacity: effects.loaderBreathingMinimumOpacity,
              breathingMaximumOpacity: effects.loaderBreathingMaximumOpacity,
              trailStrongOpacity: effects.loaderTrailStrongOpacity,
              trailMediumOpacity: effects.loaderTrailMediumOpacity,
              trailWeakOpacity: effects.loaderTrailWeakOpacity,
              plusTrailWeakOpacity: effects.loaderPlusTrailWeakOpacity,
            ),
          );
        },
      ),
    );
  }
}

/// Clockwise order from top-left:
/// (0,0) → (0,1) → (0,2) → (1,2) → (2,2) → (2,1) → (2,0) → (1,0) → (1,1).
const List<List<int>> _clockwiseOrder = [
  [0, 1, 2],
  [7, 8, 3],
  [6, 5, 4],
];

int _clockwiseIndex(int row, int col) => _clockwiseOrder[row][col];

double _phaseBreathing(int row, int col) {
  final index = row * _gridLoaderColumns + col;
  // Small offset per cell so they don’t all pulse in sync.
  return index * 0.08;
}

/// Explicit plus-sign path (no center): top, right, bottom, left.
const List<List<int>> _plusPath = [
  [0, 1], // top
  [1, 2], // right
  [2, 1], // bottom
  [1, 0], // left
];

double _breathingOpacity(double t, double minimum, double maximum) {
  final x = math.sin(t * 2 * math.pi);
  final normalized = (x + 1) / 2; // 0..1
  return minimum + (maximum - minimum) * normalized;
}

class _GridLoaderPainter extends CustomPainter {
  final double progress;
  final GridLoaderStyle style;
  final double squareSize;
  final Color color;
  final double breathingMinimumOpacity;
  final double breathingMaximumOpacity;
  final double trailStrongOpacity;
  final double trailMediumOpacity;
  final double trailWeakOpacity;
  final double plusTrailWeakOpacity;

  _GridLoaderPainter({
    required this.progress,
    required this.style,
    required this.squareSize,
    required this.color,
    required this.breathingMinimumOpacity,
    required this.breathingMaximumOpacity,
    required this.trailStrongOpacity,
    required this.trailMediumOpacity,
    required this.trailWeakOpacity,
    required this.plusTrailWeakOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (int row = 0; row < _gridLoaderRows; row++) {
      for (int col = 0; col < _gridLoaderColumns; col++) {
        double opacity;

        switch (style) {
          case GridLoaderStyle.breathingGrid:
            final phase = _phaseBreathing(row, col);
            final t = (progress + phase) % 1.0;
            opacity = _breathingOpacity(
              t,
              breathingMinimumOpacity,
              breathingMaximumOpacity,
            );
            break;

          case GridLoaderStyle.borderLoop:
            const borderLen = 8.0;
            final headPos = (progress * borderLen) % borderLen;
            final index = _clockwiseIndex(row, col);

            if (index == 8) {
              opacity = 0.0;
            } else {
              double backDist = headPos - index;
              if (backDist < 0) backDist += borderLen;
              // Head + 3 trailing squares: 1.0, 0.8, 0.55, 0.3
              if (backDist < 1.0) {
                opacity = 1.0;
              } else if (backDist < 2.0) {
                opacity = trailStrongOpacity;
              } else if (backDist < 3.0) {
                opacity = trailMediumOpacity;
              } else if (backDist < 4.0) {
                opacity = trailWeakOpacity;
              } else {
                opacity = 0.0;
              }
            }
            break;

          case GridLoaderStyle.plusLoop:
            const virtualLen = 8.0;
            final headPos = (progress * virtualLen) % virtualLen;

            int? plusIndex;
            for (var i = 0; i < _plusPath.length; i++) {
              final cell = _plusPath[i];
              if (cell[0] == row && cell[1] == col) {
                plusIndex = i;
                break;
              }
            }

            if (plusIndex == null) {
              opacity = 0.0;
            } else {
              final cellPos = plusIndex * 2.0;
              double backDist = headPos - cellPos;
              if (backDist < 0) backDist += virtualLen;
              // Head + 2 trailing squares: 1.0, 0.8, 0.5
              if (backDist < 1.0) {
                opacity = 1.0;
              } else if (backDist < 2.0) {
                opacity = trailStrongOpacity;
              } else if (backDist < 3.0) {
                opacity = plusTrailWeakOpacity;
              } else {
                opacity = 0.0;
              }
            }
            break;
        }

        if (opacity <= 0.0) continue;

        final x = col * squareSize;
        final y = row * squareSize;
        final rect = Rect.fromLTWH(x, y, squareSize, squareSize);

        paint.color = color.withValues(alpha: opacity);
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridLoaderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.style != style ||
        oldDelegate.squareSize != squareSize ||
        oldDelegate.color != color ||
        oldDelegate.breathingMinimumOpacity != breathingMinimumOpacity ||
        oldDelegate.breathingMaximumOpacity != breathingMaximumOpacity ||
        oldDelegate.trailStrongOpacity != trailStrongOpacity ||
        oldDelegate.trailMediumOpacity != trailMediumOpacity ||
        oldDelegate.trailWeakOpacity != trailWeakOpacity ||
        oldDelegate.plusTrailWeakOpacity != plusTrailWeakOpacity;
  }
}

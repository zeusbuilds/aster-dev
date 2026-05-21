import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shared.dart';

const int kGridLoaderRows = 3;
const int kGridLoaderCols = 3;

/// Opacity range for the breathing grid effect.
const double kBreathingMinOpacity = 0.35;
const double kBreathingMaxOpacity = 1.0;

/// Size presets for the 3×3 grid loader.
enum GridLoaderSize { small, medium, large }

double _squareSizeFor(GridLoaderSize size) {
  switch (size) {
    case GridLoaderSize.small:
      return 8.0; // 3 * 8 = 24px grid
    case GridLoaderSize.medium:
      return 10.0; // 30px grid
    case GridLoaderSize.large:
      return 12.0; // 36px grid
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

  /// Override square size, if you want custom sizing.
  final double? squareSize;

  /// Override animation cycle duration.
  final Duration? cycleDuration;

  /// Custom color when [colorStyle] is [GridLoaderColorStyle.custom].
  final Color? color;

  const GridLoader({
    super.key,
    this.style = GridLoaderStyle.breathingGrid,
    this.colorStyle = GridLoaderColorStyle.white,
    this.size = GridLoaderSize.small,
    this.squareSize,
    this.cycleDuration,
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
    _controller = AnimationController(
      vsync: this,
      duration:
          widget.cycleDuration ?? const AsterMotion().loadingCycleDuration,
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration =
        widget.cycleDuration ?? context.motion.loadingCycleDuration;
    if (_controller.duration != duration) {
      _controller.duration = duration;
    }
  }

  @override
  void didUpdateWidget(GridLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final duration =
        widget.cycleDuration ?? context.motion.loadingCycleDuration;
    if (_controller.duration != duration) {
      _controller.duration = duration;
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

    final squareSize = widget.squareSize ?? _squareSizeFor(widget.size);
    final gridWidth = kGridLoaderCols * squareSize;
    final gridHeight = kGridLoaderRows * squareSize;

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
  final index = row * kGridLoaderCols + col;
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

double _breathingOpacity(double t) {
  final x = math.sin(t * 2 * math.pi);
  final normalized = (x + 1) / 2; // 0..1
  return kBreathingMinOpacity +
      (kBreathingMaxOpacity - kBreathingMinOpacity) * normalized;
}

class _GridLoaderPainter extends CustomPainter {
  final double progress;
  final GridLoaderStyle style;
  final double squareSize;
  final Color color;

  _GridLoaderPainter({
    required this.progress,
    required this.style,
    required this.squareSize,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int row = 0; row < kGridLoaderRows; row++) {
      for (int col = 0; col < kGridLoaderCols; col++) {
        double opacity;

        switch (style) {
          case GridLoaderStyle.breathingGrid:
            final phase = _phaseBreathing(row, col);
            final t = (progress + phase) % 1.0;
            opacity = _breathingOpacity(t);
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
                opacity = 0.8;
              } else if (backDist < 3.0) {
                opacity = 0.55;
              } else if (backDist < 4.0) {
                opacity = 0.3;
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
                opacity = 0.8;
              } else if (backDist < 3.0) {
                opacity = 0.5;
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

        final paint = Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.fill;
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridLoaderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.style != style ||
        oldDelegate.squareSize != squareSize ||
        oldDelegate.color != color;
  }
}

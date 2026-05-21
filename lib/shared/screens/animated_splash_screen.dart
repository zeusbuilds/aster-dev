import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

const _splashMotion = AsterMotion();
final _animationDuration = _splashMotion.splashRevealDuration.inMilliseconds;

const _rotationStart = 0;
const _rotationEnd = 240;

const _expansionStart = 120;
const _expansionEnd = 520;

const _splitStart = 520;
const _splitEnd = 700;

const _linesLengthStart = 680;
const _linesLengthEnd = 1080;
const _linesGapStart = 720;
const _linesGapEnd = 1160;

/// Drives lines past the screen edge so they exit off-screen (1.0 = at edge).
const _linesGapMax = 1.3;

const _logoWidth = 160;

/// Animated splash screen used during app startup.
class AnimatedSplashScreen extends StatelessWidget {
  const AnimatedSplashScreen({required this.controller, super.key});

  final AnimationController controller;

  static AnimationController createController(TickerProvider vsync) {
    return AnimationController(
      vsync: vsync,
      duration: _splashMotion.splashRevealDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: [
          _Background(controller: controller),
          _Foreground(controller: controller),
        ],
      ),
    );
  }
}

class _Background extends StatefulWidget {
  const _Background({required this.controller});

  final AnimationController controller;

  @override
  State<_Background> createState() => _BackgroundState();
}

class _BackgroundState extends State<_Background> {
  late final Animation<double> _linesLength = Tween<double>(begin: 0, end: 1)
      .chain(
        CurveTween(
          curve: Interval(
            _linesLengthStart / _animationDuration,
            _linesLengthEnd / _animationDuration,
            curve: _splashMotion.choreographyCurve,
          ),
        ),
      )
      .animate(widget.controller);

  late final Animation<double> _linesGap =
      Tween<double>(begin: 0, end: _linesGapMax)
          .chain(
            CurveTween(
              curve: Interval(
                _linesGapStart / _animationDuration,
                _linesGapEnd / _animationDuration,
                curve: _splashMotion.splashRevealMoveCurve,
              ),
            ),
          )
          .animate(widget.controller);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return CustomPaint(
      painter: _BackgroundPainter(
        linesLength: _linesLength,
        linesGap: _linesGap,
        colors: colors.splashGradient,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter({
    required this.linesLength,
    required this.linesGap,
    required this.colors,
  }) : super(repaint: Listenable.merge([linesLength, linesGap]));

  final Animation<double> linesLength;
  final Animation<double> linesGap;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());

    final gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
        stops: const [0, 0.5, 1],
      ).createShader(rect);
    canvas.drawRect(rect, gradientPaint);

    if (linesLength.value > 0) {
      const initialLineHeight = 8.5;
      const maxLineHeight = 50.0;
      final centerY = size.height / 2;

      final lineHeight =
          initialLineHeight +
          (maxLineHeight - initialLineHeight) * linesLength.value;

      final topY = (centerY - lineHeight / 2) * (1 - linesGap.value);
      final bottomY =
          (centerY - lineHeight / 2) * (1 - linesGap.value) +
          (size.height - lineHeight) * linesGap.value;

      final clearTop = topY + lineHeight;
      final clearBottom = bottomY;

      if (clearBottom > clearTop) {
        canvas.drawRect(
          Rect.fromLTRB(0, clearTop, size.width, clearBottom),
          Paint()..blendMode = BlendMode.clear,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) {
    return linesLength != oldDelegate.linesLength ||
        linesGap != oldDelegate.linesGap ||
        colors != oldDelegate.colors;
  }
}

class _Foreground extends StatefulWidget {
  const _Foreground({required this.controller});

  final AnimationController controller;

  @override
  State<_Foreground> createState() => _ForegroundState();
}

class _ForegroundState extends State<_Foreground> {
  late final _rotation = Tween<double>(begin: 0, end: 1)
      .chain(
        CurveTween(
          curve: Interval(
            _rotationStart / _animationDuration,
            _rotationEnd / _animationDuration,
            curve: _splashMotion.choreographyCurve,
          ),
        ),
      )
      .animate(widget.controller);

  late final _expansion = Tween<double>(begin: 0, end: 1)
      .chain(
        CurveTween(
          curve: Interval(
            _expansionStart / _animationDuration,
            _expansionEnd / _animationDuration,
            curve: _splashMotion.choreographyCurve,
          ),
        ),
      )
      .animate(widget.controller);

  late final _split = Tween<double>(begin: 0, end: 1)
      .chain(
        CurveTween(
          curve: Interval(
            _splitStart / _animationDuration,
            _splitEnd / _animationDuration,
            curve: _splashMotion.splashSplitCurve,
          ),
        ),
      )
      .animate(widget.controller);

  late final _linesLength = Tween<double>(begin: 0, end: 1)
      .chain(
        CurveTween(
          curve: Interval(
            _linesLengthStart / _animationDuration,
            _linesLengthEnd / _animationDuration,
            curve: _splashMotion.choreographyCurve,
          ),
        ),
      )
      .animate(widget.controller);

  late final _linesGap = Tween<double>(begin: 0, end: _linesGapMax)
      .chain(
        CurveTween(
          curve: Interval(
            _linesGapStart / _animationDuration,
            _linesGapEnd / _animationDuration,
            curve: _splashMotion.splashRevealMoveCurve,
          ),
        ),
      )
      .animate(widget.controller);

  @override
  Widget build(BuildContext context) {
    final foregroundColor = context.appColors.onBrandArt;
    return CustomMultiChildLayout(
      delegate: _ForegroundLayoutDelegate(
        split: _split,
        linesLength: _linesLength,
        linesGap: _linesGap,
      ),
      children: [
        LayoutId(
          id: _ForegroundPart.logo,
          child: CustomPaint(
            painter: _LogoPainter(
              color: foregroundColor,
              rotation: _rotation,
              expansion: _expansion,
              linesLength: _linesLength,
            ),
          ),
        ),
        LayoutId(
          id: _ForegroundPart.topLine,
          child: ColoredBox(color: foregroundColor),
        ),
        LayoutId(
          id: _ForegroundPart.bottomLine,
          child: ColoredBox(color: foregroundColor),
        ),
      ],
    );
  }
}

enum _ForegroundPart { logo, topLine, bottomLine }

class _ForegroundLayoutDelegate extends MultiChildLayoutDelegate {
  _ForegroundLayoutDelegate({
    required this.split,
    required this.linesLength,
    required this.linesGap,
  }) : super(relayout: Listenable.merge([split, linesLength, linesGap]));

  final Animation<double> split;
  final Animation<double> linesLength;
  final Animation<double> linesGap;

  @override
  void performLayout(Size size) {
    final screenRect = Offset.zero & size;

    layoutChild(_ForegroundPart.logo, BoxConstraints.tight(size));
    positionChild(_ForegroundPart.logo, Offset.zero);

    if (linesLength.value == 0) {
      layoutChild(_ForegroundPart.topLine, BoxConstraints.tight(Size.zero));
      layoutChild(_ForegroundPart.bottomLine, BoxConstraints.tight(Size.zero));
      return;
    }

    const initialLineHeight = 8.5;
    const maxLineHeight = 50.0;
    final maxLineWidth = screenRect.width;
    final centerY = screenRect.center.dy;

    final lineHeight =
        initialLineHeight +
        (maxLineHeight - initialLineHeight) * linesLength.value;
    final lineSize = Size(maxLineWidth, lineHeight);

    layoutChild(_ForegroundPart.topLine, BoxConstraints.tight(lineSize));
    layoutChild(_ForegroundPart.bottomLine, BoxConstraints.tight(lineSize));

    final topY = (centerY - lineHeight / 2) * (1 - linesGap.value);
    final bottomY =
        (centerY - lineHeight / 2) * (1 - linesGap.value) +
        (screenRect.height - lineHeight) * linesGap.value;

    positionChild(_ForegroundPart.topLine, Offset(0, topY));
    positionChild(_ForegroundPart.bottomLine, Offset(0, bottomY));
  }

  @override
  bool shouldRelayout(_ForegroundLayoutDelegate oldDelegate) {
    return split != oldDelegate.split ||
        linesLength != oldDelegate.linesLength ||
        linesGap != oldDelegate.linesGap;
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({
    required this.color,
    required this.rotation,
    required this.expansion,
    required this.linesLength,
  }) : super(repaint: Listenable.merge([rotation, expansion, linesLength]));

  final Color color;
  final Animation<double> rotation;
  final Animation<double> expansion;
  final Animation<double> linesLength;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;

    final logoWidthFactor = _logoWidth / w;
    final logoFullWidth = w * logoWidthFactor;
    final horizontalHalfWidth = logoFullWidth / 2;

    const diagToHorizRatio = 470 / 705;
    final diagonalLength = logoFullWidth * diagToHorizRatio;

    const thicknessToHorizRatio = 35 / 705;
    final thickness = logoFullWidth * thicknessToHorizRatio;

    final center = Offset(size.width / 2, size.height / 2);
    final halfWidth =
        horizontalHalfWidth + (w / 2 - horizontalHalfWidth) * expansion.value;

    canvas
      ..save()
      ..translate(center.dx, center.dy);

    const handoffThreshold = 0.2;
    if (linesLength.value < handoffThreshold && halfWidth > 0) {
      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: halfWidth * 2,
          height: thickness,
        ),
        fillPaint,
      );
    }

    if (rotation.value < 0.98) {
      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final diagonalRect = Rect.fromCenter(
        center: Offset.zero,
        width: diagonalLength,
        height: thickness,
      );
      canvas
        ..save()
        ..rotate((math.pi / 4) * (1 - rotation.value))
        ..drawRect(diagonalRect, fillPaint)
        ..restore()
        ..save()
        ..rotate(-(math.pi / 4) * (1 - rotation.value))
        ..drawRect(diagonalRect, fillPaint)
        ..restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) {
    return color != oldDelegate.color ||
        rotation != oldDelegate.rotation ||
        expansion != oldDelegate.expansion ||
        linesLength != oldDelegate.linesLength;
  }
}

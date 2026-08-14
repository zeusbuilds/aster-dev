import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Animated splash screen used during app startup.
class AnimatedSplashScreen extends StatelessWidget {
  const AnimatedSplashScreen({required this.controller, super.key});

  final AnimationController controller;

  static AnimationController createController(TickerProvider vsync) {
    return AnimationController(
      vsync: vsync,
      duration: const AsterMotion().splashRevealDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'Opening UTEXO',
        excludeSemantics: true,
        child: RepaintBoundary(
          child: Stack(
            alignment: Alignment.center,
            children: [
              _Background(controller: controller),
              _Foreground(controller: controller),
            ],
          ),
        ),
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
  late Animation<double> _linesLength;
  late Animation<double> _linesGap;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = context.motion;
    _linesLength = Tween<double>(begin: 0, end: 1)
        .chain(
          CurveTween(
            curve: Interval(
              motion.splashLinesLengthStart,
              motion.splashLinesLengthEnd,
              curve: motion.choreographyCurve,
            ),
          ),
        )
        .animate(widget.controller);
    _linesGap = Tween<double>(begin: 0, end: context.art.splashLineGapExtent)
        .chain(
          CurveTween(
            curve: Interval(
              motion.splashLinesGapStart,
              motion.splashLinesGapEnd,
              curve: motion.splashRevealMoveCurve,
            ),
          ),
        )
        .animate(widget.controller);
  }

  @override
  Widget build(BuildContext context) {
    final gradients = context.gradients;
    return CustomPaint(
      painter: _BackgroundPainter(
        linesLength: _linesLength,
        linesGap: _linesGap,
        gradient: gradients.splashBackdrop,
        initialLineHeight: context.art.splashLineInitialHeight,
        maximumLineHeight: context.art.splashLineMaximumHeight,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter({
    required this.linesLength,
    required this.linesGap,
    required this.gradient,
    required this.initialLineHeight,
    required this.maximumLineHeight,
  }) : super(repaint: Listenable.merge([linesLength, linesGap]));

  final Animation<double> linesLength;
  final Animation<double> linesGap;
  final AsterGradientSpec gradient;
  final double initialLineHeight;
  final double maximumLineHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradientPaint = Paint()
      ..shader = gradient.toLinearGradient().createShader(rect);
    if (linesLength.value <= 0) {
      canvas.drawRect(rect, gradientPaint);
      return;
    }

    final centerY = size.height / 2;
    final lineHeight =
        initialLineHeight +
        (maximumLineHeight - initialLineHeight) * linesLength.value;
    final topY = (centerY - lineHeight / 2) * (1 - linesGap.value);
    final bottomY =
        (centerY - lineHeight / 2) * (1 - linesGap.value) +
        (size.height - lineHeight) * linesGap.value;
    final clearTop = topY + lineHeight;
    final clearBottom = bottomY;

    if (clearBottom <= clearTop) {
      canvas.drawRect(rect, gradientPaint);
      return;
    }
    canvas
      ..drawRect(Rect.fromLTRB(0, 0, size.width, clearTop), gradientPaint)
      ..drawRect(
        Rect.fromLTRB(0, clearBottom, size.width, size.height),
        gradientPaint,
      );
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) {
    return linesLength != oldDelegate.linesLength ||
        linesGap != oldDelegate.linesGap ||
        gradient != oldDelegate.gradient ||
        initialLineHeight != oldDelegate.initialLineHeight ||
        maximumLineHeight != oldDelegate.maximumLineHeight;
  }
}

class _Foreground extends StatefulWidget {
  const _Foreground({required this.controller});

  final AnimationController controller;

  @override
  State<_Foreground> createState() => _ForegroundState();
}

class _ForegroundState extends State<_Foreground> {
  late Animation<double> _rotation;
  late Animation<double> _expansion;
  late Animation<double> _linesLength;
  late Animation<double> _linesGap;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = context.motion;
    _rotation = _phaseAnimation(
      begin: motion.splashRotationStart,
      end: motion.splashRotationEnd,
      curve: motion.choreographyCurve,
    );
    _expansion = _phaseAnimation(
      begin: motion.splashExpansionStart,
      end: motion.splashExpansionEnd,
      curve: motion.choreographyCurve,
    );
    _linesLength = _phaseAnimation(
      begin: motion.splashLinesLengthStart,
      end: motion.splashLinesLengthEnd,
      curve: motion.choreographyCurve,
    );
    _linesGap = Tween<double>(begin: 0, end: context.art.splashLineGapExtent)
        .chain(
          CurveTween(
            curve: Interval(
              motion.splashLinesGapStart,
              motion.splashLinesGapEnd,
              curve: motion.splashRevealMoveCurve,
            ),
          ),
        )
        .animate(widget.controller);
  }

  Animation<double> _phaseAnimation({
    required double begin,
    required double end,
    required Curve curve,
  }) {
    return Tween<double>(begin: 0, end: 1)
        .chain(CurveTween(curve: Interval(begin, end, curve: curve)))
        .animate(widget.controller);
  }

  @override
  Widget build(BuildContext context) {
    final foregroundColor = context.appColors.onBrandArt;
    final art = context.art;
    return CustomMultiChildLayout(
      delegate: _ForegroundLayoutDelegate(
        linesLength: _linesLength,
        linesGap: _linesGap,
        initialLineHeight: art.splashLineInitialHeight,
        maximumLineHeight: art.splashLineMaximumHeight,
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
              logoWidth: context.metrics.splashLogoWidth,
              diagonalRatio: art.splashLogoDiagonalRatio,
              thicknessRatio: art.splashLogoThicknessRatio,
              handoffProgress: art.splashLogoHandoffProgress,
              diagonalExitProgress: art.splashLogoDiagonalExitProgress,
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
    required this.linesLength,
    required this.linesGap,
    required this.initialLineHeight,
    required this.maximumLineHeight,
  }) : super(relayout: Listenable.merge([linesLength, linesGap]));

  final Animation<double> linesLength;
  final Animation<double> linesGap;
  final double initialLineHeight;
  final double maximumLineHeight;

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

    final maxLineWidth = screenRect.width;
    final centerY = screenRect.center.dy;

    final lineHeight =
        initialLineHeight +
        (maximumLineHeight - initialLineHeight) * linesLength.value;
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
    return linesLength != oldDelegate.linesLength ||
        linesGap != oldDelegate.linesGap ||
        initialLineHeight != oldDelegate.initialLineHeight ||
        maximumLineHeight != oldDelegate.maximumLineHeight;
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({
    required this.color,
    required this.rotation,
    required this.expansion,
    required this.linesLength,
    required this.logoWidth,
    required this.diagonalRatio,
    required this.thicknessRatio,
    required this.handoffProgress,
    required this.diagonalExitProgress,
  }) : super(repaint: Listenable.merge([rotation, expansion, linesLength]));

  final Color color;
  final Animation<double> rotation;
  final Animation<double> expansion;
  final Animation<double> linesLength;
  final double logoWidth;
  final double diagonalRatio;
  final double thicknessRatio;
  final double handoffProgress;
  final double diagonalExitProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;

    final logoWidthFactor = logoWidth / w;
    final logoFullWidth = w * logoWidthFactor;
    final horizontalHalfWidth = logoFullWidth / 2;

    final diagonalLength = logoFullWidth * diagonalRatio;
    final thickness = logoFullWidth * thicknessRatio;

    final center = Offset(size.width / 2, size.height / 2);
    final halfWidth =
        horizontalHalfWidth + (w / 2 - horizontalHalfWidth) * expansion.value;

    canvas
      ..save()
      ..translate(center.dx, center.dy);

    if (linesLength.value < handoffProgress && halfWidth > 0) {
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

    if (rotation.value < diagonalExitProgress) {
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
        linesLength != oldDelegate.linesLength ||
        logoWidth != oldDelegate.logoWidth ||
        diagonalRatio != oldDelegate.diagonalRatio ||
        thicknessRatio != oldDelegate.thicknessRatio ||
        handoffProgress != oldDelegate.handoffProgress ||
        diagonalExitProgress != oldDelegate.diagonalExitProgress;
  }
}

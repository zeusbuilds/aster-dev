import 'package:flutter/material.dart';

import '../branding/aster_launch_logo.dart';
import '../branding/aster_logo_geometry.dart';
import '../theme/theme.dart';

/// Animated splash screen used during app startup.
class AnimatedSplashScreen extends StatelessWidget {
  const AnimatedSplashScreen({
    required this.controller,
    this.colorTransition = const AlwaysStoppedAnimation(1),
    super.key,
  });

  final Animation<double> controller;

  /// Runs while the mark is stationary, before the existing reveal begins.
  final Animation<double> colorTransition;

  static AnimationController createController(TickerProvider vsync) {
    return AnimationController(
      vsync: vsync,
      duration: const AsterMotion().splashRevealDuration,
    );
  }

  static AnimationController createColorTransitionController(
    TickerProvider vsync,
  ) => AnimationController(
    vsync: vsync,
    duration: const AsterMotion().splashColorTransitionDuration,
  );

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'Opening Aster',
        excludeSemantics: true,
        child: RepaintBoundary(
          child: Stack(
            alignment: Alignment.center,
            children: [
              _Background(controller: controller),
              _Foreground(
                controller: controller,
                colorTransition: colorTransition,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Background extends StatefulWidget {
  const _Background({required this.controller});

  final Animation<double> controller;

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
    return CustomPaint(
      painter: _BackgroundPainter(
        linesLength: _linesLength,
        linesGap: _linesGap,
        initialLineHeight: AsterLogoGeometry.horizontalThicknessForWidth(
          context.metrics.splashLogoWidth,
        ),
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
    required this.initialLineHeight,
    required this.maximumLineHeight,
  }) : super(repaint: Listenable.merge([linesLength, linesGap]));

  final Animation<double> linesLength;
  final Animation<double> linesGap;
  final double initialLineHeight;
  final double maximumLineHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // The opening surface stays white through the fill transition and reveal.
    // Only the reveal geometry uncovers the app underneath.
    final backgroundPaint = Paint()..color = AsterColors.launchSurface;
    if (linesLength.value <= 0) {
      canvas.drawRect(rect, backgroundPaint);
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
      canvas.drawRect(rect, backgroundPaint);
      return;
    }
    canvas
      ..drawRect(Rect.fromLTRB(0, 0, size.width, clearTop), backgroundPaint)
      ..drawRect(
        Rect.fromLTRB(0, clearBottom, size.width, size.height),
        backgroundPaint,
      );
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) {
    return linesLength != oldDelegate.linesLength ||
        linesGap != oldDelegate.linesGap ||
        initialLineHeight != oldDelegate.initialLineHeight ||
        maximumLineHeight != oldDelegate.maximumLineHeight;
  }
}

class _Foreground extends StatefulWidget {
  const _Foreground({required this.controller, required this.colorTransition});

  final Animation<double> controller;
  final Animation<double> colorTransition;

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
    final foregroundColor = context.appColors.brandArtMain;
    final art = context.art;
    return CustomMultiChildLayout(
      delegate: _ForegroundLayoutDelegate(
        linesLength: _linesLength,
        linesGap: _linesGap,
        initialLineHeight: AsterLogoGeometry.horizontalThicknessForWidth(
          context.metrics.splashLogoWidth,
        ),
        maximumLineHeight: art.splashLineMaximumHeight,
      ),
      children: [
        LayoutId(
          id: _ForegroundPart.logo,
          child: CustomPaint(
            painter: _LogoPainter(
              color: foregroundColor,
              colorTransition: widget.colorTransition,
              rotation: _rotation,
              expansion: _expansion,
              linesLength: _linesLength,
              logoWidth: context.metrics.splashLogoWidth,
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
    required this.colorTransition,
    required this.rotation,
    required this.expansion,
    required this.linesLength,
    required this.logoWidth,
    required this.handoffProgress,
    required this.diagonalExitProgress,
  }) : super(
         repaint: Listenable.merge([
           rotation,
           expansion,
           linesLength,
           colorTransition,
         ]),
       );

  final Color color;
  final Animation<double> colorTransition;
  final Animation<double> rotation;
  final Animation<double> expansion;
  final Animation<double> linesLength;
  final double logoWidth;
  final double handoffProgress;
  final double diagonalExitProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final horizontalWidth =
        logoWidth + (size.width - logoWidth) * expansion.value;
    final path = AsterLogoGeometry.animatedPath(
      logoWidth: logoWidth,
      horizontalWidth: horizontalWidth,
      rotationProgress: rotation.value,
      expansionProgress: expansion.value,
      includeHorizontal: linesLength.value < handoffProgress,
      includeDiagonals: rotation.value < diagonalExitProgress,
    );
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2);
    AsterLaunchLogo.paint(
      canvas,
      path: path,
      logoBounds: Rect.fromCenter(
        center: Offset.zero,
        width: logoWidth,
        height:
            logoWidth *
            AsterLogoGeometry.size.height /
            AsterLogoGeometry.size.width,
      ),
      blueColor: color,
      finalColor: color,
      colorProgress: colorTransition.value,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) {
    return color != oldDelegate.color ||
        colorTransition != oldDelegate.colorTransition ||
        rotation != oldDelegate.rotation ||
        expansion != oldDelegate.expansion ||
        linesLength != oldDelegate.linesLength ||
        logoWidth != oldDelegate.logoWidth ||
        handoffProgress != oldDelegate.handoffProgress ||
        diagonalExitProgress != oldDelegate.diagonalExitProgress;
  }
}

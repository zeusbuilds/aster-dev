import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/theme.dart';

/// Decorative mark for a selected item whose owning row handles interaction.
///
/// Its expanding fill and check reproduce Aster's original radio choreography
/// without giving this decorative child a second interaction or semantic node.
class AsterSelectionIndicator extends StatefulWidget {
  const AsterSelectionIndicator({super.key, required this.selected});

  final bool selected;

  @override
  State<AsterSelectionIndicator> createState() =>
      _AsterSelectionIndicatorState();
}

class _AsterSelectionIndicatorState extends State<AsterSelectionIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  CurvedAnimation? _progress;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: widget.selected ? 1 : 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = context.motion;
    final progress = _progress;
    if (progress == null) {
      _progress = CurvedAnimation(
        parent: _controller,
        curve: motion.selectionCurve,
        reverseCurve: motion.selectionReverseCurve,
      );
    } else {
      progress
        ..curve = motion.selectionCurve
        ..reverseCurve = motion.selectionReverseCurve;
    }
    _duration = context.motionPolicy.duration(
      motion.selectionTransitionDuration,
    );
    _controller
      ..duration = _duration
      ..reverseDuration = _duration;
    if (_duration == Duration.zero && _controller.isAnimating) {
      _controller.value = widget.selected ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(covariant AsterSelectionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    if (_duration == Duration.zero) {
      _controller.value = widget.selected ? 1 : 0;
      return;
    }
    if (widget.selected) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _progress?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = context.metrics.selectionIndicatorSize;

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _AsterSelectionPainter(
            progress: _progress!,
            activeColor: context.colorScheme.primary,
            inactiveBorderColor: context.colorScheme.surfaceContainerHigh,
            inactiveFillColor: context.colorScheme.surface,
            checkColor: context.colorScheme.onPrimary,
            strokeWidth: context.strokes.selectionIndicator,
          ),
        ),
      ),
    );
  }
}

class _AsterSelectionPainter extends CustomPainter {
  _AsterSelectionPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveBorderColor,
    required this.inactiveFillColor,
    required this.checkColor,
    required this.strokeWidth,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color activeColor;
  final Color inactiveBorderColor;
  final Color inactiveFillColor;
  final Color checkColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final value = progress.value.clamp(0.0, 1.0);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()
      ..isAntiAlias = true
      ..color = Color.lerp(inactiveBorderColor, activeColor, value)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, paint);

    if (value == 0) {
      paint
        ..color = inactiveFillColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, paint);
      return;
    }

    paint
      ..color = activeColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * value, paint);

    final checkBounds = Rect.fromCircle(center: center, radius: radius * value);
    final check = Path()
      ..moveTo(
        checkBounds.left + checkBounds.width * 0.25,
        checkBounds.top + checkBounds.height * 0.5,
      )
      ..lineTo(
        checkBounds.left + checkBounds.width * 0.45,
        checkBounds.top + checkBounds.height * 0.7,
      )
      ..lineTo(
        checkBounds.left + checkBounds.width * 0.75,
        checkBounds.top + checkBounds.height * 0.3,
      );
    paint
      ..color = checkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(check, paint);
  }

  @override
  bool shouldRepaint(covariant _AsterSelectionPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveBorderColor != inactiveBorderColor ||
        oldDelegate.inactiveFillColor != inactiveFillColor ||
        oldDelegate.checkColor != checkColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

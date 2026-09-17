import 'package:flutter/cupertino.dart';

import 'theme_context.dart';

final Animatable<Offset> _incomingPageOffset = Tween<Offset>(
  begin: const Offset(1, 0),
  end: Offset.zero,
);
final Animatable<Offset> _coveredPageOffset = Tween<Offset>(
  begin: Offset.zero,
  end: const Offset(-1 / 3, 0),
);

/// Cupertino's native page motion without Flutter's painted edge shadow.
///
/// Flutter's public transition does not expose a shadow toggle. The standard
/// builder is still invoked so its private interactive back-swipe detector is
/// retained; only the visual transition wrapper is replaced. Timing, curves,
/// parallax, text direction, and linear gesture tracking mirror Flutter's
/// [CupertinoPageTransition].
final class AsterCupertinoPageTransitionsBuilder
    extends CupertinoPageTransitionsBuilder {
  const AsterCupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final standard = super.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
    if (standard is! CupertinoPageTransition) return standard;
    final motion = context.motion;
    return _AsterCupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: route.popGestureInProgress,
      incomingCurve: motion.cupertinoPageIncomingCurve,
      coveredCurve: motion.cupertinoPageCoveredCurve,
      coveredReverseCurve: motion.cupertinoPageCoveredReverseCurve,
      // The standard transition's child owns Flutter's private edge-swipe
      // detector. Reusing it preserves native interactive-back behavior.
      child: standard.child,
    );
  }
}

class _AsterCupertinoPageTransition extends StatefulWidget {
  const _AsterCupertinoPageTransition({
    required this.primaryRouteAnimation,
    required this.secondaryRouteAnimation,
    required this.linearTransition,
    required this.incomingCurve,
    required this.coveredCurve,
    required this.coveredReverseCurve,
    required this.child,
  });

  final Animation<double> primaryRouteAnimation;
  final Animation<double> secondaryRouteAnimation;
  final bool linearTransition;
  final Curve incomingCurve;
  final Curve coveredCurve;
  final Curve coveredReverseCurve;
  final Widget child;

  @override
  State<_AsterCupertinoPageTransition> createState() =>
      _AsterCupertinoPageTransitionState();
}

class _AsterCupertinoPageTransitionState
    extends State<_AsterCupertinoPageTransition> {
  late Animation<Offset> _primaryPosition;
  late Animation<Offset> _secondaryPosition;
  CurvedAnimation? _primaryCurve;
  CurvedAnimation? _secondaryCurve;

  @override
  void initState() {
    super.initState();
    _configureAnimations();
  }

  @override
  void didUpdateWidget(_AsterCupertinoPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryRouteAnimation != widget.primaryRouteAnimation ||
        oldWidget.secondaryRouteAnimation != widget.secondaryRouteAnimation ||
        oldWidget.linearTransition != widget.linearTransition ||
        oldWidget.incomingCurve != widget.incomingCurve ||
        oldWidget.coveredCurve != widget.coveredCurve ||
        oldWidget.coveredReverseCurve != widget.coveredReverseCurve) {
      _disposeCurves();
      _configureAnimations();
    }
  }

  @override
  void dispose() {
    _disposeCurves();
    super.dispose();
  }

  void _configureAnimations() {
    if (!widget.linearTransition) {
      _primaryCurve = CurvedAnimation(
        parent: widget.primaryRouteAnimation,
        curve: widget.incomingCurve,
        reverseCurve: widget.incomingCurve.flipped,
      );
      _secondaryCurve = CurvedAnimation(
        parent: widget.secondaryRouteAnimation,
        curve: widget.coveredCurve,
        reverseCurve: widget.coveredReverseCurve,
      );
    }
    _primaryPosition = (_primaryCurve ?? widget.primaryRouteAnimation).drive(
      _incomingPageOffset,
    );
    _secondaryPosition = (_secondaryCurve ?? widget.secondaryRouteAnimation)
        .drive(_coveredPageOffset);
  }

  void _disposeCurves() {
    _primaryCurve?.dispose();
    _secondaryCurve?.dispose();
    _primaryCurve = null;
    _secondaryCurve = null;
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _secondaryPosition,
      textDirection: Directionality.of(context),
      transformHitTests: false,
      child: SlideTransition(
        position: _primaryPosition,
        textDirection: Directionality.of(context),
        child: widget.child,
      ),
    );
  }
}

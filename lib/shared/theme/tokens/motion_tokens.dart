import 'package:flutter/material.dart';

/// Motion decisions shared by reusable components and screen choreography.
@immutable
class AsterMotion extends ThemeExtension<AsterMotion> {
  const AsterMotion({
    this.buttonPressDuration = const Duration(milliseconds: 100),
    this.selectionTransitionDuration = const Duration(milliseconds: 150),
    this.navIndicatorDuration = const Duration(milliseconds: 150),
    this.toastTransitionDuration = const Duration(milliseconds: 300),
    this.toastVisibleDuration = const Duration(seconds: 3),
    this.bootstrapRevealDelay = const Duration(milliseconds: 500),
    this.splashRevealDuration = const Duration(milliseconds: 1250),
    this.skeletonShimmerDuration = const Duration(milliseconds: 1200),
    this.loadingCycleDuration = const Duration(milliseconds: 1200),
    this.chartLoadingCycleDuration = const Duration(milliseconds: 1500),
    this.chartTransitionDuration = const Duration(milliseconds: 800),
    this.swapKeyboardTransitionDuration = const Duration(milliseconds: 300),
    this.swapMessageTransitionDuration = const Duration(milliseconds: 400),
    this.swapDetailsRevealDuration = const Duration(milliseconds: 1200),
    this.swapDetailsDismissDuration = const Duration(milliseconds: 300),
    this.swapCancelStaggerDelay = const Duration(milliseconds: 100),
    this.buttonPressedScale = 0.95,
    this.swapDetailStaggerStep = 0.15,
    this.swapDetailRevealWindow = 0.85,
    this.settledLoopProgress = 0.25,
    this.splashRotationStart = 0,
    this.splashRotationEnd = 0.192,
    this.splashExpansionStart = 0.096,
    this.splashExpansionEnd = 0.416,
    this.splashSplitStart = 0.416,
    this.splashSplitEnd = 0.56,
    this.splashLinesLengthStart = 0.544,
    this.splashLinesLengthEnd = 0.864,
    this.splashLinesGapStart = 0.576,
    this.splashLinesGapEnd = 0.928,
    this.fastEase = Curves.easeInOut,
    this.navIndicatorCurve = Curves.fastOutSlowIn,
    this.toastCurve = Curves.easeOut,
    this.fadeInCurve = Curves.easeIn,
    this.fadeOutCurve = Curves.easeIn,
    this.choreographyCurve = Curves.easeOutCubic,
    this.splashSplitCurve = Curves.easeInOutCubic,
    this.splashRevealMoveCurve = Curves.easeInOutCubic,
    this.chartTransitionCurve = Curves.easeInOut,
  });

  final Duration buttonPressDuration;
  final Duration selectionTransitionDuration;
  final Duration navIndicatorDuration;
  final Duration toastTransitionDuration;
  final Duration toastVisibleDuration;
  final Duration bootstrapRevealDelay;
  final Duration splashRevealDuration;
  final Duration skeletonShimmerDuration;
  final Duration loadingCycleDuration;
  final Duration chartLoadingCycleDuration;
  final Duration chartTransitionDuration;
  final Duration swapKeyboardTransitionDuration;
  final Duration swapMessageTransitionDuration;
  final Duration swapDetailsRevealDuration;
  final Duration swapDetailsDismissDuration;
  final Duration swapCancelStaggerDelay;
  final double buttonPressedScale;
  final double swapDetailStaggerStep;
  final double swapDetailRevealWindow;
  final double settledLoopProgress;
  final double splashRotationStart;
  final double splashRotationEnd;
  final double splashExpansionStart;
  final double splashExpansionEnd;
  final double splashSplitStart;
  final double splashSplitEnd;
  final double splashLinesLengthStart;
  final double splashLinesLengthEnd;
  final double splashLinesGapStart;
  final double splashLinesGapEnd;
  final Curve fastEase;
  final Curve navIndicatorCurve;
  final Curve toastCurve;
  final Curve fadeInCurve;
  final Curve fadeOutCurve;
  final Curve choreographyCurve;
  final Curve splashSplitCurve;
  final Curve splashRevealMoveCurve;
  final Curve chartTransitionCurve;

  @override
  AsterMotion copyWith({
    Duration? buttonPressDuration,
    Duration? selectionTransitionDuration,
    Duration? navIndicatorDuration,
    Duration? toastTransitionDuration,
    Duration? toastVisibleDuration,
    Duration? bootstrapRevealDelay,
    Duration? splashRevealDuration,
    Duration? skeletonShimmerDuration,
    Duration? loadingCycleDuration,
    Duration? chartLoadingCycleDuration,
    Duration? chartTransitionDuration,
    Duration? swapKeyboardTransitionDuration,
    Duration? swapMessageTransitionDuration,
    Duration? swapDetailsRevealDuration,
    Duration? swapDetailsDismissDuration,
    Duration? swapCancelStaggerDelay,
    double? buttonPressedScale,
    double? swapDetailStaggerStep,
    double? swapDetailRevealWindow,
    double? settledLoopProgress,
    double? splashRotationStart,
    double? splashRotationEnd,
    double? splashExpansionStart,
    double? splashExpansionEnd,
    double? splashSplitStart,
    double? splashSplitEnd,
    double? splashLinesLengthStart,
    double? splashLinesLengthEnd,
    double? splashLinesGapStart,
    double? splashLinesGapEnd,
    Curve? fastEase,
    Curve? navIndicatorCurve,
    Curve? toastCurve,
    Curve? fadeInCurve,
    Curve? fadeOutCurve,
    Curve? choreographyCurve,
    Curve? splashSplitCurve,
    Curve? splashRevealMoveCurve,
    Curve? chartTransitionCurve,
  }) {
    return AsterMotion(
      buttonPressDuration: buttonPressDuration ?? this.buttonPressDuration,
      selectionTransitionDuration:
          selectionTransitionDuration ?? this.selectionTransitionDuration,
      navIndicatorDuration: navIndicatorDuration ?? this.navIndicatorDuration,
      toastTransitionDuration:
          toastTransitionDuration ?? this.toastTransitionDuration,
      toastVisibleDuration: toastVisibleDuration ?? this.toastVisibleDuration,
      bootstrapRevealDelay: bootstrapRevealDelay ?? this.bootstrapRevealDelay,
      splashRevealDuration: splashRevealDuration ?? this.splashRevealDuration,
      skeletonShimmerDuration:
          skeletonShimmerDuration ?? this.skeletonShimmerDuration,
      loadingCycleDuration: loadingCycleDuration ?? this.loadingCycleDuration,
      chartLoadingCycleDuration:
          chartLoadingCycleDuration ?? this.chartLoadingCycleDuration,
      chartTransitionDuration:
          chartTransitionDuration ?? this.chartTransitionDuration,
      swapKeyboardTransitionDuration:
          swapKeyboardTransitionDuration ?? this.swapKeyboardTransitionDuration,
      swapMessageTransitionDuration:
          swapMessageTransitionDuration ?? this.swapMessageTransitionDuration,
      swapDetailsRevealDuration:
          swapDetailsRevealDuration ?? this.swapDetailsRevealDuration,
      swapDetailsDismissDuration:
          swapDetailsDismissDuration ?? this.swapDetailsDismissDuration,
      swapCancelStaggerDelay:
          swapCancelStaggerDelay ?? this.swapCancelStaggerDelay,
      buttonPressedScale: buttonPressedScale ?? this.buttonPressedScale,
      swapDetailStaggerStep:
          swapDetailStaggerStep ?? this.swapDetailStaggerStep,
      swapDetailRevealWindow:
          swapDetailRevealWindow ?? this.swapDetailRevealWindow,
      settledLoopProgress: settledLoopProgress ?? this.settledLoopProgress,
      splashRotationStart: splashRotationStart ?? this.splashRotationStart,
      splashRotationEnd: splashRotationEnd ?? this.splashRotationEnd,
      splashExpansionStart: splashExpansionStart ?? this.splashExpansionStart,
      splashExpansionEnd: splashExpansionEnd ?? this.splashExpansionEnd,
      splashSplitStart: splashSplitStart ?? this.splashSplitStart,
      splashSplitEnd: splashSplitEnd ?? this.splashSplitEnd,
      splashLinesLengthStart:
          splashLinesLengthStart ?? this.splashLinesLengthStart,
      splashLinesLengthEnd: splashLinesLengthEnd ?? this.splashLinesLengthEnd,
      splashLinesGapStart: splashLinesGapStart ?? this.splashLinesGapStart,
      splashLinesGapEnd: splashLinesGapEnd ?? this.splashLinesGapEnd,
      fastEase: fastEase ?? this.fastEase,
      navIndicatorCurve: navIndicatorCurve ?? this.navIndicatorCurve,
      toastCurve: toastCurve ?? this.toastCurve,
      fadeInCurve: fadeInCurve ?? this.fadeInCurve,
      fadeOutCurve: fadeOutCurve ?? this.fadeOutCurve,
      choreographyCurve: choreographyCurve ?? this.choreographyCurve,
      splashSplitCurve: splashSplitCurve ?? this.splashSplitCurve,
      splashRevealMoveCurve:
          splashRevealMoveCurve ?? this.splashRevealMoveCurve,
      chartTransitionCurve: chartTransitionCurve ?? this.chartTransitionCurve,
    );
  }

  @override
  AsterMotion lerp(ThemeExtension<AsterMotion>? other, double t) {
    if (other is! AsterMotion) return this;
    return AsterMotion(
      buttonPressDuration: _lerpDuration(
        buttonPressDuration,
        other.buttonPressDuration,
        t,
      ),
      selectionTransitionDuration: _lerpDuration(
        selectionTransitionDuration,
        other.selectionTransitionDuration,
        t,
      ),
      navIndicatorDuration: _lerpDuration(
        navIndicatorDuration,
        other.navIndicatorDuration,
        t,
      ),
      toastTransitionDuration: _lerpDuration(
        toastTransitionDuration,
        other.toastTransitionDuration,
        t,
      ),
      toastVisibleDuration: _lerpDuration(
        toastVisibleDuration,
        other.toastVisibleDuration,
        t,
      ),
      bootstrapRevealDelay: _lerpDuration(
        bootstrapRevealDelay,
        other.bootstrapRevealDelay,
        t,
      ),
      splashRevealDuration: _lerpDuration(
        splashRevealDuration,
        other.splashRevealDuration,
        t,
      ),
      skeletonShimmerDuration: _lerpDuration(
        skeletonShimmerDuration,
        other.skeletonShimmerDuration,
        t,
      ),
      loadingCycleDuration: _lerpDuration(
        loadingCycleDuration,
        other.loadingCycleDuration,
        t,
      ),
      chartLoadingCycleDuration: _lerpDuration(
        chartLoadingCycleDuration,
        other.chartLoadingCycleDuration,
        t,
      ),
      chartTransitionDuration: _lerpDuration(
        chartTransitionDuration,
        other.chartTransitionDuration,
        t,
      ),
      swapKeyboardTransitionDuration: _lerpDuration(
        swapKeyboardTransitionDuration,
        other.swapKeyboardTransitionDuration,
        t,
      ),
      swapMessageTransitionDuration: _lerpDuration(
        swapMessageTransitionDuration,
        other.swapMessageTransitionDuration,
        t,
      ),
      swapDetailsRevealDuration: _lerpDuration(
        swapDetailsRevealDuration,
        other.swapDetailsRevealDuration,
        t,
      ),
      swapDetailsDismissDuration: _lerpDuration(
        swapDetailsDismissDuration,
        other.swapDetailsDismissDuration,
        t,
      ),
      swapCancelStaggerDelay: _lerpDuration(
        swapCancelStaggerDelay,
        other.swapCancelStaggerDelay,
        t,
      ),
      buttonPressedScale: _lerp(
        buttonPressedScale,
        other.buttonPressedScale,
        t,
      ),
      swapDetailStaggerStep: _lerp(
        swapDetailStaggerStep,
        other.swapDetailStaggerStep,
        t,
      ),
      swapDetailRevealWindow: _lerp(
        swapDetailRevealWindow,
        other.swapDetailRevealWindow,
        t,
      ),
      settledLoopProgress: _lerp(
        settledLoopProgress,
        other.settledLoopProgress,
        t,
      ),
      splashRotationStart: _lerp(
        splashRotationStart,
        other.splashRotationStart,
        t,
      ),
      splashRotationEnd: _lerp(splashRotationEnd, other.splashRotationEnd, t),
      splashExpansionStart: _lerp(
        splashExpansionStart,
        other.splashExpansionStart,
        t,
      ),
      splashExpansionEnd: _lerp(
        splashExpansionEnd,
        other.splashExpansionEnd,
        t,
      ),
      splashSplitStart: _lerp(splashSplitStart, other.splashSplitStart, t),
      splashSplitEnd: _lerp(splashSplitEnd, other.splashSplitEnd, t),
      splashLinesLengthStart: _lerp(
        splashLinesLengthStart,
        other.splashLinesLengthStart,
        t,
      ),
      splashLinesLengthEnd: _lerp(
        splashLinesLengthEnd,
        other.splashLinesLengthEnd,
        t,
      ),
      splashLinesGapStart: _lerp(
        splashLinesGapStart,
        other.splashLinesGapStart,
        t,
      ),
      splashLinesGapEnd: _lerp(splashLinesGapEnd, other.splashLinesGapEnd, t),
      fastEase: t < 0.5 ? fastEase : other.fastEase,
      navIndicatorCurve: t < 0.5 ? navIndicatorCurve : other.navIndicatorCurve,
      toastCurve: t < 0.5 ? toastCurve : other.toastCurve,
      fadeInCurve: t < 0.5 ? fadeInCurve : other.fadeInCurve,
      fadeOutCurve: t < 0.5 ? fadeOutCurve : other.fadeOutCurve,
      choreographyCurve: t < 0.5 ? choreographyCurve : other.choreographyCurve,
      splashSplitCurve: t < 0.5 ? splashSplitCurve : other.splashSplitCurve,
      splashRevealMoveCurve: t < 0.5
          ? splashRevealMoveCurve
          : other.splashRevealMoveCurve,
      chartTransitionCurve: t < 0.5
          ? chartTransitionCurve
          : other.chartTransitionCurve,
    );
  }

  static Duration _lerpDuration(Duration a, Duration b, double t) {
    return Duration(
      microseconds: _lerp(
        a.inMicroseconds.toDouble(),
        b.inMicroseconds.toDouble(),
        t,
      ).round(),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

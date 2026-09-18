import 'package:flutter/material.dart';

/// Motion decisions shared by reusable components and screen choreography.
@immutable
class AsterMotion extends ThemeExtension<AsterMotion> {
  const AsterMotion({
    this.buttonPressDuration = const Duration(milliseconds: 100),
    this.buttonMinimumPressedDuration = const Duration(milliseconds: 100),
    this.selectionTransitionDuration = const Duration(milliseconds: 200),
    this.selectionCommitDelay = const Duration(milliseconds: 250),
    this.contentTransitionDuration = const Duration(milliseconds: 420),
    this.onboardingStepTransitionDuration = const Duration(milliseconds: 900),
    this.onboardingStepIndicatorTransitionDuration = const Duration(
      milliseconds: 500,
    ),
    this.contentTransitionIncomingStart = 0.5,
    this.contentTransitionOutgoingEnd = 0.5,
    this.contentTransitionVerticalOffset = 12,
    this.choreographyItemInterval = 0.2,
    this.choreographyStaggerInterval = 0.1,
    this.navIndicatorDuration = const Duration(milliseconds: 150),
    this.toastTransitionDuration = const Duration(milliseconds: 300),
    this.toastVisibleDuration = const Duration(seconds: 3),
    this.bootstrapRevealDelay = const Duration(milliseconds: 500),
    this.splashRevealDuration = const Duration(milliseconds: 1250),
    this.skeletonShimmerDuration = const Duration(milliseconds: 1200),
    this.loadingCycleDuration = const Duration(milliseconds: 1200),
    this.chartLoadingCycleDuration = const Duration(milliseconds: 1500),
    this.chartTransitionDuration = const Duration(milliseconds: 800),
    this.buttonPressedScale = 0.95,
    this.settledLoopProgress = 0.25,
    this.splashRotationStart = 0,
    this.splashRotationEnd = 0.192,
    this.splashExpansionStart = 0.096,
    this.splashExpansionEnd = 0.416,
    this.splashLinesLengthStart = 0.544,
    this.splashLinesLengthEnd = 0.864,
    this.splashLinesGapStart = 0.576,
    this.splashLinesGapEnd = 0.928,
    this.fastEase = Curves.easeInOut,
    this.selectionCurve = Curves.easeIn,
    this.selectionReverseCurve = Curves.easeOut,
    this.navIndicatorCurve = Curves.fastOutSlowIn,
    this.toastCurve = Curves.easeOut,
    this.choreographyCurve = Curves.easeOutCubic,
    this.splashRevealMoveCurve = Curves.easeInOutCubic,
    this.chartTransitionCurve = Curves.easeInOut,
    this.cupertinoPageIncomingCurve = Curves.fastEaseInToSlowEaseOut,
    this.cupertinoPageCoveredCurve = Curves.linearToEaseOut,
    this.cupertinoPageCoveredReverseCurve = Curves.easeInToLinear,
  }) : assert(
         contentTransitionIncomingStart >= 0 &&
             contentTransitionIncomingStart <= 1,
       ),
       assert(
         contentTransitionOutgoingEnd >= 0 && contentTransitionOutgoingEnd <= 1,
       ),
       assert(
         contentTransitionOutgoingEnd <= contentTransitionIncomingStart,
         'Fade-through content must finish exiting before it enters.',
       ),
       assert(contentTransitionVerticalOffset >= 0),
       assert(choreographyItemInterval > 0 && choreographyItemInterval <= 1),
       assert(
         choreographyStaggerInterval >= 0 && choreographyStaggerInterval <= 1,
       );

  final Duration buttonPressDuration;

  /// Keeps a quick tap visibly pressed long enough to render at least one
  /// complete scale-down transition before the button returns to rest.
  final Duration buttonMinimumPressedDuration;
  final Duration selectionTransitionDuration;

  /// Keeps a committed selection visible before its owning route dismisses.
  final Duration selectionCommitDelay;
  final Duration contentTransitionDuration;

  /// Deliberate handoff shared by every step in the onboarding journey.
  final Duration onboardingStepTransitionDuration;

  /// Rail resize kept close to, but slightly ahead of, the page handoff.
  final Duration onboardingStepIndicatorTransitionDuration;

  /// Normalized point at which incoming content starts to appear.
  final double contentTransitionIncomingStart;

  /// Normalized point by which outgoing content is fully hidden.
  final double contentTransitionOutgoingEnd;

  /// Logical pixels traveled by content while entering or leaving.
  final double contentTransitionVerticalOffset;

  /// Normalized time allocated to one item in a staggered composition.
  final double choreographyItemInterval;

  /// Normalized delay between adjacent items in a staggered composition.
  final double choreographyStaggerInterval;

  final Duration navIndicatorDuration;
  final Duration toastTransitionDuration;
  final Duration toastVisibleDuration;
  final Duration bootstrapRevealDelay;
  final Duration splashRevealDuration;
  final Duration skeletonShimmerDuration;
  final Duration loadingCycleDuration;
  final Duration chartLoadingCycleDuration;
  final Duration chartTransitionDuration;
  final double buttonPressedScale;
  final double settledLoopProgress;
  final double splashRotationStart;
  final double splashRotationEnd;
  final double splashExpansionStart;
  final double splashExpansionEnd;
  final double splashLinesLengthStart;
  final double splashLinesLengthEnd;
  final double splashLinesGapStart;
  final double splashLinesGapEnd;
  final Curve fastEase;
  final Curve selectionCurve;
  final Curve selectionReverseCurve;
  final Curve navIndicatorCurve;
  final Curve toastCurve;
  final Curve choreographyCurve;
  final Curve splashRevealMoveCurve;
  final Curve chartTransitionCurve;
  final Curve cupertinoPageIncomingCurve;
  final Curve cupertinoPageCoveredCurve;
  final Curve cupertinoPageCoveredReverseCurve;

  @override
  AsterMotion copyWith({
    Duration? buttonPressDuration,
    Duration? buttonMinimumPressedDuration,
    Duration? selectionTransitionDuration,
    Duration? selectionCommitDelay,
    Duration? contentTransitionDuration,
    Duration? onboardingStepTransitionDuration,
    Duration? onboardingStepIndicatorTransitionDuration,
    double? contentTransitionIncomingStart,
    double? contentTransitionOutgoingEnd,
    double? contentTransitionVerticalOffset,
    double? choreographyItemInterval,
    double? choreographyStaggerInterval,
    Duration? navIndicatorDuration,
    Duration? toastTransitionDuration,
    Duration? toastVisibleDuration,
    Duration? bootstrapRevealDelay,
    Duration? splashRevealDuration,
    Duration? skeletonShimmerDuration,
    Duration? loadingCycleDuration,
    Duration? chartLoadingCycleDuration,
    Duration? chartTransitionDuration,
    double? buttonPressedScale,
    double? settledLoopProgress,
    double? splashRotationStart,
    double? splashRotationEnd,
    double? splashExpansionStart,
    double? splashExpansionEnd,
    double? splashLinesLengthStart,
    double? splashLinesLengthEnd,
    double? splashLinesGapStart,
    double? splashLinesGapEnd,
    Curve? fastEase,
    Curve? selectionCurve,
    Curve? selectionReverseCurve,
    Curve? navIndicatorCurve,
    Curve? toastCurve,
    Curve? choreographyCurve,
    Curve? splashRevealMoveCurve,
    Curve? chartTransitionCurve,
    Curve? cupertinoPageIncomingCurve,
    Curve? cupertinoPageCoveredCurve,
    Curve? cupertinoPageCoveredReverseCurve,
  }) {
    return AsterMotion(
      buttonPressDuration: buttonPressDuration ?? this.buttonPressDuration,
      buttonMinimumPressedDuration:
          buttonMinimumPressedDuration ?? this.buttonMinimumPressedDuration,
      selectionTransitionDuration:
          selectionTransitionDuration ?? this.selectionTransitionDuration,
      selectionCommitDelay: selectionCommitDelay ?? this.selectionCommitDelay,
      contentTransitionDuration:
          contentTransitionDuration ?? this.contentTransitionDuration,
      onboardingStepTransitionDuration:
          onboardingStepTransitionDuration ??
          this.onboardingStepTransitionDuration,
      onboardingStepIndicatorTransitionDuration:
          onboardingStepIndicatorTransitionDuration ??
          this.onboardingStepIndicatorTransitionDuration,
      contentTransitionIncomingStart:
          contentTransitionIncomingStart ?? this.contentTransitionIncomingStart,
      contentTransitionOutgoingEnd:
          contentTransitionOutgoingEnd ?? this.contentTransitionOutgoingEnd,
      contentTransitionVerticalOffset:
          contentTransitionVerticalOffset ??
          this.contentTransitionVerticalOffset,
      choreographyItemInterval:
          choreographyItemInterval ?? this.choreographyItemInterval,
      choreographyStaggerInterval:
          choreographyStaggerInterval ?? this.choreographyStaggerInterval,
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
      buttonPressedScale: buttonPressedScale ?? this.buttonPressedScale,
      settledLoopProgress: settledLoopProgress ?? this.settledLoopProgress,
      splashRotationStart: splashRotationStart ?? this.splashRotationStart,
      splashRotationEnd: splashRotationEnd ?? this.splashRotationEnd,
      splashExpansionStart: splashExpansionStart ?? this.splashExpansionStart,
      splashExpansionEnd: splashExpansionEnd ?? this.splashExpansionEnd,
      splashLinesLengthStart:
          splashLinesLengthStart ?? this.splashLinesLengthStart,
      splashLinesLengthEnd: splashLinesLengthEnd ?? this.splashLinesLengthEnd,
      splashLinesGapStart: splashLinesGapStart ?? this.splashLinesGapStart,
      splashLinesGapEnd: splashLinesGapEnd ?? this.splashLinesGapEnd,
      fastEase: fastEase ?? this.fastEase,
      selectionCurve: selectionCurve ?? this.selectionCurve,
      selectionReverseCurve:
          selectionReverseCurve ?? this.selectionReverseCurve,
      navIndicatorCurve: navIndicatorCurve ?? this.navIndicatorCurve,
      toastCurve: toastCurve ?? this.toastCurve,
      choreographyCurve: choreographyCurve ?? this.choreographyCurve,
      splashRevealMoveCurve:
          splashRevealMoveCurve ?? this.splashRevealMoveCurve,
      chartTransitionCurve: chartTransitionCurve ?? this.chartTransitionCurve,
      cupertinoPageIncomingCurve:
          cupertinoPageIncomingCurve ?? this.cupertinoPageIncomingCurve,
      cupertinoPageCoveredCurve:
          cupertinoPageCoveredCurve ?? this.cupertinoPageCoveredCurve,
      cupertinoPageCoveredReverseCurve:
          cupertinoPageCoveredReverseCurve ??
          this.cupertinoPageCoveredReverseCurve,
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
      buttonMinimumPressedDuration: _lerpDuration(
        buttonMinimumPressedDuration,
        other.buttonMinimumPressedDuration,
        t,
      ),
      selectionTransitionDuration: _lerpDuration(
        selectionTransitionDuration,
        other.selectionTransitionDuration,
        t,
      ),
      selectionCommitDelay: _lerpDuration(
        selectionCommitDelay,
        other.selectionCommitDelay,
        t,
      ),
      contentTransitionDuration: _lerpDuration(
        contentTransitionDuration,
        other.contentTransitionDuration,
        t,
      ),
      onboardingStepTransitionDuration: _lerpDuration(
        onboardingStepTransitionDuration,
        other.onboardingStepTransitionDuration,
        t,
      ),
      onboardingStepIndicatorTransitionDuration: _lerpDuration(
        onboardingStepIndicatorTransitionDuration,
        other.onboardingStepIndicatorTransitionDuration,
        t,
      ),
      contentTransitionIncomingStart: _lerp(
        contentTransitionIncomingStart,
        other.contentTransitionIncomingStart,
        t,
      ),
      contentTransitionOutgoingEnd: _lerp(
        contentTransitionOutgoingEnd,
        other.contentTransitionOutgoingEnd,
        t,
      ),
      contentTransitionVerticalOffset: _lerp(
        contentTransitionVerticalOffset,
        other.contentTransitionVerticalOffset,
        t,
      ),
      choreographyItemInterval: _lerp(
        choreographyItemInterval,
        other.choreographyItemInterval,
        t,
      ),
      choreographyStaggerInterval: _lerp(
        choreographyStaggerInterval,
        other.choreographyStaggerInterval,
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
      buttonPressedScale: _lerp(
        buttonPressedScale,
        other.buttonPressedScale,
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
      selectionCurve: t < 0.5 ? selectionCurve : other.selectionCurve,
      selectionReverseCurve: t < 0.5
          ? selectionReverseCurve
          : other.selectionReverseCurve,
      navIndicatorCurve: t < 0.5 ? navIndicatorCurve : other.navIndicatorCurve,
      toastCurve: t < 0.5 ? toastCurve : other.toastCurve,
      choreographyCurve: t < 0.5 ? choreographyCurve : other.choreographyCurve,
      splashRevealMoveCurve: t < 0.5
          ? splashRevealMoveCurve
          : other.splashRevealMoveCurve,
      chartTransitionCurve: t < 0.5
          ? chartTransitionCurve
          : other.chartTransitionCurve,
      cupertinoPageIncomingCurve: t < 0.5
          ? cupertinoPageIncomingCurve
          : other.cupertinoPageIncomingCurve,
      cupertinoPageCoveredCurve: t < 0.5
          ? cupertinoPageCoveredCurve
          : other.cupertinoPageCoveredCurve,
      cupertinoPageCoveredReverseCurve: t < 0.5
          ? cupertinoPageCoveredReverseCurve
          : other.cupertinoPageCoveredReverseCurve,
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

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Keeps the branded onboarding background alive across its nested routes.
///
/// The mesh owns fragment shaders and a full-screen filtered layer. Housing it
/// above the onboarding navigator prevents route transitions from composing
/// two copies or recreating those resources for every step.
class OnboardingShell extends StatefulWidget {
  const OnboardingShell({super.key, required this.child});

  /// Active onboarding route rendered over the retained background.
  final Widget child;

  @override
  State<OnboardingShell> createState() => _OnboardingShellState();
}

class _OnboardingShellState extends State<OnboardingShell> {
  // Bounds the retained RGBA texture to roughly 15 MiB on large phones while
  // preserving native density on the 3x devices this artwork targets.
  static const _maximumBackgroundSnapshotPixelRatio = 3.0;

  late final SnapshotController _backgroundSnapshot;

  @override
  void initState() {
    super.initState();
    _backgroundSnapshot = SnapshotController();
  }

  @override
  void dispose() {
    _backgroundSnapshot.dispose();
    super.dispose();
  }

  void _enableBackgroundSnapshot() {
    if (!_backgroundSnapshot.allowSnapshotting) {
      _backgroundSnapshot.allowSnapshotting = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mediaQuery = MediaQuery.of(context);
    final snapshotPixelRatio = math.min(
      mediaQuery.devicePixelRatio,
      _maximumBackgroundSnapshotPixelRatio,
    );
    final baseTheme = Theme.of(context);
    final transitionBuilders =
        Map<TargetPlatform, PageTransitionsBuilder>.unmodifiable({
          ...baseTheme.pageTransitionsTheme.builders,
          TargetPlatform.android:
              PredictiveBackFullscreenPageTransitionsBuilder(
                fallbackColor: colors.transparentSurface,
              ),
        });
    final onboardingTheme = baseTheme.copyWith(
      pageTransitionsTheme: PageTransitionsTheme(builders: transitionBuilders),
    );

    return ColoredBox(
      color: colors.brandArtDark,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaQuery(
            data: mediaQuery.copyWith(devicePixelRatio: snapshotPixelRatio),
            child: SnapshotWidget(
              controller: _backgroundSnapshot,
              autoresize: true,
              child: OnboardingWelcomeMeshBackground(
                onCompositionReady: _enableBackgroundSnapshot,
              ),
            ),
          ),
          Theme(data: onboardingTheme, child: widget.child),
        ],
      ),
    );
  }
}

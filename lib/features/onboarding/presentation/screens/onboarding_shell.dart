import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
  late final OnboardingBackgroundSnapshotPainter _backgroundSnapshotPainter;

  @override
  void initState() {
    super.initState();
    _backgroundSnapshot = SnapshotController();
    _backgroundSnapshotPainter = OnboardingBackgroundSnapshotPainter();
  }

  @override
  void dispose() {
    _backgroundSnapshot.dispose();
    _backgroundSnapshotPainter.dispose();
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
              painter: _backgroundSnapshotPainter,
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

/// Paints and reports the retained onboarding background snapshot.
///
/// [SnapshotController.allowSnapshotting] only grants permission to capture;
/// it does not prove that [SnapshotWidget] has produced an image. This painter
/// mirrors Flutter's default rendering and exposes the stronger invariant used
/// by the profile gate: a real snapshot reached the paint pipeline.
final class OnboardingBackgroundSnapshotPainter extends SnapshotPainter {
  /// Whether a real snapshot image has been painted at least once.
  bool get hasPaintedSnapshot => _hasPaintedSnapshot;
  bool _hasPaintedSnapshot = false;

  /// Physical source dimensions of the most recently painted snapshot.
  Size? get physicalSize => _physicalSize;
  Size? _physicalSize;

  /// Device-pixel ratio used for the most recently painted snapshot.
  double? get pixelRatio => _pixelRatio;
  double? _pixelRatio;

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback painter,
  ) {
    _hasPaintedSnapshot = false;
    _physicalSize = null;
    _pixelRatio = null;
    painter(context, offset);
  }

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    final source = Rect.fromLTWH(0, 0, sourceSize.width, sourceSize.height);
    final destination = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      size.width,
      size.height,
    );
    context.canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()..filterQuality = FilterQuality.medium,
    );
    _hasPaintedSnapshot = true;
    _physicalSize = sourceSize;
    _pixelRatio = pixelRatio;
  }

  @override
  bool shouldRepaint(
    covariant OnboardingBackgroundSnapshotPainter oldPainter,
  ) => false;
}

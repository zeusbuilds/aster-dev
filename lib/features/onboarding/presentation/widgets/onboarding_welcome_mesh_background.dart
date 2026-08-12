import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mesh/mesh.dart';

import '../../../../shared/shared.dart';

/// Blue mesh gradient background used on the onboarding welcome screen.
class OnboardingWelcomeMeshBackground extends StatefulWidget {
  const OnboardingWelcomeMeshBackground({super.key, this.onCompositionReady});

  /// Called once both the mesh and noise texture have completed a paintable frame.
  final VoidCallback? onCompositionReady;

  @override
  State<OnboardingWelcomeMeshBackground> createState() =>
      _OnboardingWelcomeMeshBackgroundState();
}

class _OnboardingWelcomeMeshBackgroundState
    extends State<OnboardingWelcomeMeshBackground> {
  var _meshReady = false;
  var _noiseReady = false;
  var _didNotifyCompositionReady = false;

  void _markMeshReady() {
    if (_meshReady) return;
    _meshReady = true;
    _notifyCompositionReadyIfPossible();
  }

  void _markNoiseReady() {
    if (_noiseReady) return;
    _noiseReady = true;
    _notifyCompositionReadyIfPossible();
  }

  void _notifyCompositionReadyIfPossible() {
    if (!_meshReady ||
        !_noiseReady ||
        _didNotifyCompositionReady ||
        widget.onCompositionReady == null) {
      return;
    }
    _didNotifyCompositionReady = true;
    widget.onCompositionReady?.call();
  }

  @override
  void didUpdateWidget(OnboardingWelcomeMeshBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _notifyCompositionReadyIfPossible();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final art = context.art;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: art.brandMeshBlurSigma,
              sigmaY: art.brandMeshBlurSigma,
            ),
            child: _MeshPaintObserver(
              onPainted: _markMeshReady,
              child: OMeshGradient(
                mesh: OMeshRect(
                  width: art.onboardingMeshColumns,
                  height: art.onboardingMeshRows,
                  fallbackColor: colors.brandArtDark,
                  backgroundColor: colors.brandArtDeep,
                  vertices: [
                    (-0.04, 0.0).v,
                    (0.24, 0.0).v,
                    (0.51, 0.0).v,
                    (0.74, 0.0).v,
                    (1.04, 0.0).v,

                    (-0.04, 0.14).v,
                    (0.25, 0.14).v,
                    (0.51, 0.14).v,
                    (0.75, 0.14).v,
                    (1.04, 0.14).v,

                    (-0.04, 0.32).v,
                    (0.15, 0.32).v,
                    (0.48, 0.32).v,
                    (0.81, 0.32).v,
                    (1.04, 0.32).v,

                    (-0.04, 0.50).v,
                    (
                      0.15,
                      0.50,
                    ).v.bezier(east: (0.30, 0.50).v, west: (0.05, 0.50).v),
                    (
                      0.48,
                      0.50,
                    ).v.bezier(east: (0.68, 0.50).v, west: (0.30, 0.50).v),
                    (
                      0.81,
                      0.50,
                    ).v.bezier(east: (0.92, 0.50).v, west: (0.68, 0.50).v),
                    (1.04, 0.50).v,

                    (-0.04, 0.66).v,
                    (
                      0.15,
                      0.66,
                    ).v.bezier(east: (0.28, 0.66).v, west: (0.07, 0.66).v),
                    (
                      0.48,
                      0.66,
                    ).v.bezier(east: (0.70, 0.66).v, west: (0.28, 0.66).v),
                    (0.92, 0.66).v.bezier(north: (0.92, 0.66).v),
                    (1.04, 0.66).v,

                    (-0.04, 0.85).v,
                    (0.35, 0.85).v,
                    (0.65, 0.85).v,
                    (0.93, 0.85).v,
                    (1.04, 0.85).v,

                    (-0.04, 1.0).v,
                    (0.35, 1.0).v,
                    (0.65, 1.0).v,
                    (0.93, 1.0).v,
                    (1.04, 1.0).v,
                  ],
                  colors: [
                    // Dark frame keeps white onboarding content readable.
                    colors.brandArtDark,
                    colors.brandArtDeep,
                    colors.brandArtDeep,
                    colors.brandArtDeep,
                    colors.brandArtDark,

                    colors.brandArtDark,
                    colors.brandArtDeep,
                    colors.brandArtMain,
                    colors.brandArtDeep,
                    colors.brandArtDark,

                    // Blue bloom sits behind the icon grid, not directly behind copy.
                    colors.brandArtDark,
                    colors.brandArtDeep,
                    colors.brandArtBright,
                    colors.brandArtMain,
                    colors.brandArtDeep,

                    colors.brandArtDark,
                    colors.brandArtDeep,
                    colors.brandArtMain,
                    colors.brandArtBright,
                    colors.brandArtDeep,

                    colors.brandArtDark,
                    colors.brandArtDeep,
                    colors.brandArtMain,
                    colors.brandArtDeep,
                    colors.brandArtDark,

                    colors.brandArtDark,
                    colors.brandArtDark,
                    colors.brandArtDeep,
                    colors.brandArtDeep,
                    colors.brandArtDeep,

                    colors.brandArtDark,
                    colors.brandArtDark,
                    colors.brandArtDeep,
                    colors.brandArtDark,
                    colors.brandArtDark,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AsterNoiseTexture(onImageReady: _markNoiseReady),
          ),
        ],
      ),
    );
  }
}

/// Observes the package's own renderer without replacing its optimized path.
///
/// `OMeshGradient` initially builds an empty box while its shader loads. Its
/// private shader loader does not expose readiness, so this observer waits
/// until the resulting custom painter is in the render subtree and has been
/// painted before allowing the parent to freeze the composition.
class _MeshPaintObserver extends SingleChildRenderObjectWidget {
  const _MeshPaintObserver({required this.onPainted, required super.child});

  final VoidCallback onPainted;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeshPaintObserver(onPainted);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeshPaintObserver renderObject,
  ) {
    renderObject.onPainted = onPainted;
  }
}

class _RenderMeshPaintObserver extends RenderProxyBox {
  _RenderMeshPaintObserver(this._onPainted);

  VoidCallback _onPainted;
  bool _didReportReady = false;
  bool _readyCallbackScheduled = false;

  set onPainted(VoidCallback value) => _onPainted = value;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_didReportReady ||
        _readyCallbackScheduled ||
        !_containsCustomPainter(child)) {
      return;
    }

    _readyCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readyCallbackScheduled = false;
      if (!attached || _didReportReady) return;
      _didReportReady = true;
      _onPainted();
    });
  }

  bool _containsCustomPainter(RenderObject? root) {
    if (root == null) return false;
    if (root is RenderCustomPaint && root.painter != null) return true;

    var found = false;
    root.visitChildren((child) {
      if (!found) found = _containsCustomPainter(child);
    });
    return found;
  }
}

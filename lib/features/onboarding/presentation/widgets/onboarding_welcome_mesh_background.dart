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
    final scheme = context.colorScheme;
    final art = context.art;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _MeshPaintObserver(
            onPainted: _markMeshReady,
            child: OMeshGradient(
              mesh: OMeshRect(
                width: art.onboardingMeshColumns,
                height: art.onboardingMeshRows,
                fallbackColor: colors.brandArtDeep,
                backgroundColor: colors.brandArtDeep,
                vertices: [
                  (0.0, 0.0).v,
                  (0.3, 0.0).v,
                  (0.7, 0.0).v,
                  (1.0, 0.0).v,
                  (0.0, 0.3).v,
                  (0.2, 0.4).v,
                  (0.7, 0.2).v,
                  (1.0, 0.3).v,
                  (0.0, 0.7).v,
                  (0.3, 0.8).v,
                  (0.7, 0.6).v,
                  (1.0, 0.7).v,
                  (0.0, 1.0).v,
                  (0.3, 1.0).v,
                  (0.7, 1.0).v,
                  (1.0, 1.0).v,
                ],
                colors: [
                  colors.brandArtMain,
                  colors.brandArtDeep,
                  colors.brandArtMain,
                  colors.brandArtSoft,
                  colors.brandArtBright,
                  colors.brandArtMain,
                  colors.brandArtBright,
                  colors.brandArtSoft,
                  scheme.primary,
                  colors.brandArtBright,
                  colors.brandArtSoft,
                  scheme.primary,
                  colors.brandArtSoft,
                  scheme.primary,
                  colors.brandArtBright,
                  colors.brandArtMain,
                ],
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

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mesh/mesh.dart';

import '../../../../shared/shared.dart';

/// Blue mesh gradient background used on the onboarding welcome screen.
class OnboardingWelcomeMeshBackground extends StatelessWidget {
  const OnboardingWelcomeMeshBackground({super.key, this.onTextureReady});

  /// Called once the noise texture can be captured without a blank frame.
  final VoidCallback? onTextureReady;

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
          Positioned.fill(
            child: AsterNoiseTexture(onImageReady: onTextureReady),
          ),
        ],
      ),
    );
  }
}

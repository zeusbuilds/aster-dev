import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:mesh/mesh.dart';

import '../../../../shared/shared.dart';

/// Authored home backdrop with a blurred mesh and subtle noise texture.
class MeshGradientBackground extends StatelessWidget {
  const MeshGradientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effects = context.effects;
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
                width: art.homeMeshColumns,
                height: art.homeMeshRows,
                fallbackColor: colors.brandArtDark,
                backgroundColor: colors.brandArtSoft,
                vertices: [
                  (-0.06, 0.0).v,
                  (0.24, 0.0).v,
                  (0.51, 0.0).v,
                  (0.74, 0.0).v,
                  (1.03, 0.0).v, // Row 1 - Top (0%) - Black

                  (-0.04, 0.12).v,
                  (0.25, 0.12).v,
                  (0.51, 0.12).v,
                  (0.75, 0.12).v,
                  (1.03, 0.12).v, // Row 2 - 12% - Black

                  (-0.05, 0.35).v,
                  (0.15, 0.35).v,
                  (0.48, 0.35).v,
                  (0.81, 0.35).v,
                  (1.03, 0.35).v, // Row 3 - 35% - Dark Blue

                  (-0.06, 0.50).v,
                  (
                    0.15,
                    0.50,
                  ).v.bezier(east: (0.25, 0.50).v, west: (0.05, 0.50).v),
                  (
                    0.48,
                    0.50,
                  ).v.bezier(east: (0.66, 0.50).v, west: (0.3, 0.50).v),
                  (
                    0.81,
                    0.50,
                  ).v.bezier(east: (0.89, 0.50).v, west: (0.68, 0.50).v),
                  (1.03, 0.50).v, // Row 4 - 50% - Bright Blue

                  (-0.06, 0.65).v,
                  (
                    0.15,
                    0.65,
                  ).v.bezier(east: (0.25, 0.65).v, west: (0.07, 0.65).v),
                  (
                    0.48,
                    0.65,
                  ).v.bezier(east: (0.69, 0.65).v, west: (0.28, 0.65).v),
                  (0.92, 0.65).v.bezier(north: (0.92, 0.65).v),
                  (1.03, 0.65).v, // Row 5 - 65% - Lighter Blue

                  (-0.03, 0.88).v,
                  (0.35, 0.88).v,
                  (0.65, 0.88).v,
                  (0.93, 0.88).v,
                  (1.07, 0.88).v, // Row 6 - 88% - Light Blue

                  (-0.03, 1.0).v,
                  (0.35, 1.0).v,
                  (0.65, 1.0).v,
                  (0.93, 1.0).v,
                  (1.07, 1.0).v, // Row 7 - Bottom (100%) - Light Blue
                ],
                colors: [
                  // Row 1 - Top (0%) - Black
                  colors.brandArtDark,
                  colors.brandArtDark,
                  colors.brandArtDark,
                  colors.brandArtDark,
                  colors.brandArtDark,

                  // Row 2 - 12% - Black
                  colors.brandArtDark,
                  colors.brandArtDark,
                  colors.brandArtDark,
                  colors.brandArtDark,
                  colors.brandArtDark,

                  // Row 3 - 35% - Dark Blue
                  colors.brandArtDeep,
                  colors.brandArtDeep,
                  colors.brandArtDeep,
                  colors.brandArtDeep,
                  colors.brandArtDeep,

                  // Row 4 - 50% - Bright Blue
                  colors.brandArtMain,
                  colors.brandArtMain,
                  colors.brandArtMain,
                  colors.brandArtMain,
                  colors.brandArtMain,

                  // Row 5 - 65% - Lighter Blue
                  colors.brandArtBright,
                  colors.brandArtBright,
                  colors.brandArtBright,
                  colors.brandArtBright,
                  colors.brandArtBright,

                  // Row 6 - 88% - Light Blue
                  colors.brandArtSoft,
                  colors.brandArtSoft,
                  colors.brandArtSoft,
                  colors.brandArtSoft,
                  colors.brandArtSoft,

                  // Row 7 - Bottom (100%) - Light Blue
                  colors.brandArtSoft,
                  colors.brandArtSoft,
                  colors.brandArtSoft,
                  colors.brandArtSoft,
                  colors.brandArtSoft,
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: effects.artNoiseOpacity,
              child: Image.asset(
                'assets/texture/noise.jpg',
                fit: BoxFit.cover,
                color: colors.artNoiseTint.withValues(
                  alpha: effects.artNoiseTintOpacity,
                ),
                colorBlendMode: BlendMode.overlay,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

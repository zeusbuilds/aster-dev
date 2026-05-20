import 'package:flutter/material.dart';
import 'package:mesh/mesh.dart';

import '../../../../shared/shared.dart';

/// Blue mesh gradient background used on the onboarding welcome screen.
class OnboardingWelcomeMeshBackground extends StatelessWidget {
  const OnboardingWelcomeMeshBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Stack(
      fit: StackFit.expand,
      children: [
        OMeshGradient(
          mesh: OMeshRect(
            width: 5,
            height: 7,
            fallbackColor: colors.brandArtDark,
            backgroundColor: colors.brandArtMain,
            // Left column at x=0 and right at x=1 so edges stay straight during slide transitions.
            vertices: [
              (0.0, 0.0).v,
              (0.24, 0.0).v,
              (0.51, 0.0).v,
              (0.74, 0.0).v,
              (1.0, 0.0).v,

              (0.0, 0.14).v,
              (0.25, 0.14).v,
              (0.51, 0.14).v,
              (0.75, 0.14).v,
              (1.0, 0.14).v,

              (0.0, 0.32).v,
              (0.15, 0.32).v,
              (0.48, 0.32).v,
              (0.81, 0.32).v,
              (1.0, 0.32).v,

              (0.0, 0.50).v,
              (0.15, 0.50).v.bezier(east: (0.30, 0.50).v, west: (0.05, 0.50).v),
              (0.48, 0.50).v.bezier(east: (0.68, 0.50).v, west: (0.30, 0.50).v),
              (0.81, 0.50).v.bezier(east: (0.92, 0.50).v, west: (0.68, 0.50).v),
              (1.0, 0.50).v,

              (0.0, 0.66).v,
              (0.15, 0.66).v.bezier(east: (0.28, 0.66).v, west: (0.07, 0.66).v),
              (0.48, 0.66).v.bezier(east: (0.70, 0.66).v, west: (0.28, 0.66).v),
              (0.92, 0.66).v.bezier(north: (0.92, 0.66).v),
              (1.0, 0.66).v,

              (0.0, 0.85).v,
              (0.35, 0.85).v,
              (0.65, 0.85).v,
              (0.93, 0.85).v,
              (1.0, 0.85).v,

              (0.0, 1.0).v,
              (0.35, 1.0).v,
              (0.65, 1.0).v,
              (0.93, 1.0).v,
              (1.0, 1.0).v,
            ],
            colors: [
              // Row 1 - Top: light mesh blue (~8BD0FF) with slight variation
              AsterColors.blue300,
              AsterColors.blue300,
              colors.brandArtSoft,
              colors.brandArtSoft,
              colors.brandArtSoft,

              // Row 2: transition toward the mid-light blue band
              colors.brandArtBright,
              colors.brandArtBright,
              colors.brandArtBright,
              AsterColors.blue300,
              AsterColors.blue300,

              // Row 3: mid-light blue band (~007BFF) drifting downward
              AsterColors.blue800,
              AsterColors.blue800,
              colors.brandArtMain,
              colors.brandArtBright,
              colors.brandArtBright,

              // Row 4: bright theme blue (~001AFF) blooming toward the right
              colors.brandArtDeep,
              colors.brandArtDeep,
              colors.brandArtMain,
              colors.brandArtMain,
              AsterColors.blue800,

              // Row 5: classic theme dark blue (~000C79) into bright core
              colors.brandArtDark,
              colors.brandArtDeep,
              colors.brandArtDeep,
              colors.brandArtDeep,
              colors.brandArtMain,

              // Row 6: dark blue band, beginning diagonal from right to left
              colors.brandArtDark,
              colors.brandArtDark,
              colors.brandArtDark,
              colors.brandArtDeep,
              colors.brandArtDeep,

              // Row 7 - Bottom: darkest blues near black
              colors.brandArtDark,
              colors.brandArtDark,
              colors.brandArtDark,
              colors.brandArtDark,
              colors.brandArtDeep,
            ],
          ),
        ),
      ],
    );
  }
}

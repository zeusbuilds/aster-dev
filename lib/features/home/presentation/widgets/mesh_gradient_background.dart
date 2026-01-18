import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mesh/mesh.dart';

/// Background widget with animated mesh gradient effect
/// Creates a blue gradient mesh with blur and noise texture overlay
class MeshGradientBackground extends StatelessWidget {
  const MeshGradientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The Mesh Gradient (Background)
        OMeshGradient(
          mesh: OMeshRect(
            width: 5,
            height: 7,
            fallbackColor: const Color(0xff000000),
            backgroundColor: const Color(0xff8BD0FF),
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
              (0.15, 0.50).v.bezier(east: (0.25, 0.50).v, west: (0.05, 0.50).v),
              (0.48, 0.50).v.bezier(east: (0.66, 0.50).v, west: (0.3, 0.50).v),
              (0.81, 0.50).v.bezier(east: (0.89, 0.50).v, west: (0.68, 0.50).v),
              (1.03, 0.50).v, // Row 4 - 50% - Bright Blue

              (-0.06, 0.65).v,
              (0.15, 0.65).v.bezier(east: (0.25, 0.65).v, west: (0.07, 0.65).v),
              (0.48, 0.65).v.bezier(east: (0.69, 0.65).v, west: (0.28, 0.65).v),
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
            colors: const [
              // Row 1 - Top (0%) - Black
              Color(0xff000000),
              Color(0xff000000),
              Color(0xff000000),
              Color(0xff000000),
              Color(0xff000000),

              // Row 2 - 12% - Black
              Color(0xff000000),
              Color(0xff000000),
              Color(0xff000000),
              Color(0xff000000),
              Color(0xff000000),

              // Row 3 - 35% - Dark Blue
              Color(0xff000C79),
              Color(0xff000C79),
              Color(0xff000C79),
              Color(0xff000C79),
              Color(0xff000C79),

              // Row 4 - 50% - Bright Blue
              Color(0xff001AFF),
              Color(0xff001AFF),
              Color(0xff001AFF),
              Color(0xff001AFF),
              Color(0xff001AFF),

              // Row 5 - 65% - Lighter Blue
              Color(0xff007BFF),
              Color(0xff007BFF),
              Color(0xff007BFF),
              Color(0xff007BFF),
              Color(0xff007BFF),

              // Row 6 - 88% - Light Blue
              Color(0xff8BD0FF),
              Color(0xff8BD0FF),
              Color(0xff8BD0FF),
              Color(0xff8BD0FF),
              Color(0xff8BD0FF),

              // Row 7 - Bottom (100%) - Light Blue
              Color(0xff8BD0FF),
              Color(0xff8BD0FF),
              Color(0xff8BD0FF),
              Color(0xff8BD0FF),
              Color(0xff8BD0FF),
            ],
          ),
        ),

        // Backdrop filter for blur effect
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            color: Colors.transparent, // Required to apply filter
          ),
        ),

        // Noise texture overlay
        Positioned.fill(
          child: Opacity(
            opacity: 0.05,
            child: Image.asset(
              'assets/texture/noise.jpg',
              fit: BoxFit.cover,
              color: Colors.black.withValues(alpha: 0.5),
              colorBlendMode: BlendMode.overlay,
            ),
          ),
        ),
      ],
    );
  }
}

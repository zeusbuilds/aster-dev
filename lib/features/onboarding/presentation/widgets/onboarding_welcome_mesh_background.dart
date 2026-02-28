import 'package:flutter/material.dart';
import 'package:mesh/mesh.dart';

/// Blue mesh gradient background used on the onboarding welcome screen.
class OnboardingWelcomeMeshBackground extends StatelessWidget {
  const OnboardingWelcomeMeshBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        OMeshGradient(
          mesh: OMeshRect(
            width: 5,
            height: 7,
            fallbackColor: const Color(0xFF000000),
            backgroundColor: const Color(0xFF001AFF),
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
            colors: const [
              // Row 1 - Top: light mesh blue (~8BD0FF) with slight variation
              Color(0xff7FD2FF),
              Color(0xff86D6FF),
              Color(0xff8BD8FF),
              Color(0xff90DBFF),
              Color(0xff96DEFF),

              // Row 2: transition toward the mid-light blue band
              Color(0xff4FBFFF),
              Color(0xff5BC5FF),
              Color(0xff67CBFF),
              Color(0xff73D1FF),
              Color(0xff7FD6FF),

              // Row 3: mid-light blue band (~007BFF) drifting downward
              Color(0xff0057D8),
              Color(0xff0062E0),
              Color(0xff006EEE),
              Color(0xff0077F8),
              Color(0xff0080FF),

              // Row 4: bright theme blue (~001AFF) blooming toward the right
              Color(0xff0014A5),
              Color(0xff001AB2),
              Color(0xff0021C0),
              Color(0xff002BD0),
              Color(0xff0035E0),

              // Row 5: classic theme dark blue (~000C79) into bright core
              Color(0xff000C79),
              Color(0xff001083),
              Color(0xff00168F),
              Color(0xff001F9F),
              Color(0xff0028B0),

              // Row 6: dark blue band, beginning diagonal from right to left
              Color(0xff000A28),
              Color(0xff001037),
              Color(0xff001750),
              Color(0xff001F6E),
              Color(0xff00288E),

              // Row 7 - Bottom: darkest blues near black
              Color(0xff00040B),
              Color(0xff000A1A),
              Color(0xff001233),
              Color(0xff001B4F),
              Color(0xff00276E),
            ],
          ),
        ),
      ],
    );
  }
}

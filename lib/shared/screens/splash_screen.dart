import 'package:flutter/material.dart';

import 'package:flutter_svg/svg.dart';

import '../theme/theme.dart';

/// Splash screen with gradient background and centered logo
///
/// Displays the app logo in the center with a gradient background
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final gradients = context.gradients;
    final metrics = context.metrics;

    return BlockSemantics(
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'Opening wallet',
        excludeSemantics: true,
        child: Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: gradients.splashBackdrop.toLinearGradient(),
            ),
            child: Center(
              child: SvgPicture.asset(
                'assets/brand/utexo-mark.svg',
                width: metrics.splashLogoWidth,
                colorFilter: ColorFilter.mode(
                  colors.onBrandArt,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

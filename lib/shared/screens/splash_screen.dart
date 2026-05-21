import 'package:flutter/material.dart';

import 'package:flutter_svg/svg.dart';

import '../shared.dart';

/// Splash screen with gradient background and centered logo
///
/// Displays the app logo in the center with a gradient background
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors.splashGradient,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: SvgPicture.asset(
            'assets/brand/aster-logo.svg',
            width: spacing.heroInset,
            colorFilter: ColorFilter.mode(colors.onBrandArt, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}

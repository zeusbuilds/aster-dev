import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import 'animated_splash_screen.dart';

/// Static, opaque artwork shared by loading, lock and privacy covers.
///
/// Reusing the stopped opening frame keeps every cover identical to startup:
/// a white surface with the blue gradient mark and its outside shadows.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => BlockSemantics(
    child: Semantics(
      container: true,
      liveRegion: true,
      label: 'Opening wallet',
      excludeSemantics: true,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: context.appColors.transparentSurface,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: context.appColors.transparentSurface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: const AnimatedSplashScreen(
          controller: AlwaysStoppedAnimation(0),
          colorTransition: AlwaysStoppedAnimation(0),
        ),
      ),
    ),
  );
}

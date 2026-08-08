import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Main home screen displaying wallet balance, Bitcoin price, and asset list
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.metrics;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final topPadding = context.windowInsets.topSystem;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: colors.transparentSurface,
        statusBarIconBrightness: Brightness.light, // White icons for Android
        statusBarBrightness: Brightness.dark, // Dark background for iOS
      ),
      child: Scaffold(
        backgroundColor: context.colorScheme.surface,
        body: Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: screenHeight * metrics.homeHeroHeightFactor,
                  width: double.infinity,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const MeshGradientBackground(),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: topPadding),
                            const HomeHeader(),
                            const PriceCard(),
                            SizedBox(height: context.spacing.lg),
                            const HomeActionButtons(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const AssetsSection(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

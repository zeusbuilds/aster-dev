import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Main home screen displaying wallet balance, Bitcoin price, and asset list
///
/// Manages GDK session and balance fetching for the active wallet
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // Ticker forces a rebuild every frame for animated static
    _ticker = createTicker((elapsed) {
      setState(() {
        // Time-based animation updates can be added here if needed
      });
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Set status bar to light (white icons) for home screen
      value: const SystemUiOverlayStyle(
        statusBarColor: AsterColors.transparent,
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
                  height: MediaQuery.of(context).size.height * 0.4,
                  width: double.infinity,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const MeshGradientBackground(),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).padding.top,
                            ),
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

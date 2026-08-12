import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../home/presentation/screens/home_screen.dart';
import '../../../market/presentation/screens/market_screen.dart';
import '../../../scan/domain/models/models.dart';
import '../../../scan/presentation/screens/scan_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../providers/skeleton_index_provider.dart';
import '../widgets/bottom_nav.dart';

/// Main shell containing the persistent navigation and feature screen stack.
class SkeletonScreen extends ConsumerWidget {
  const SkeletonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(skeletonIndexProvider);

    final screens = <Widget>[
      const HomeScreen(),
      const ScanScreen(purpose: ScanPurpose.sendLauncher),
      const MarketScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: index,
            children: [
              for (
                var screenIndex = 0;
                screenIndex < screens.length;
                screenIndex += 1
              )
                TickerMode(
                  enabled: screenIndex == index,
                  child: IgnorePointer(
                    ignoring: screenIndex != index,
                    child: screenIndex == index
                        ? screens[screenIndex]
                        : ExcludeSemantics(child: screens[screenIndex]),
                  ),
                ),
            ],
          ),
          const BottomNav(),
        ],
      ),
    );
  }
}

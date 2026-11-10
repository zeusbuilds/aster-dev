import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/shared.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../market/presentation/screens/market_screen.dart';
import '../../../scan/domain/models/models.dart';
import '../../../scan/presentation/screens/scan_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../providers/app_shell_index_provider.dart';
import '../widgets/bottom_nav.dart';

/// Main shell containing the persistent navigation and feature screen stack.
class AppShellScreen extends ConsumerWidget {
  const AppShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(appShellIndexProvider);
    final cover = ref.watch(duoCoverLayoutProvider).value;
    final isDuoCover = cover?.appliesTo(MediaQuery.sizeOf(context)) == true;

    final screens = <Widget>[
      const HomeScreen(),
      const ScanScreen(purpose: ScanPurpose.sendLauncher),
      MarketScreen(isDuoCover: isDuoCover),
      const SettingsScreen(),
    ];
    final coverRail = CoverTabRail.resolve(context, cover, appShellTabCount);

    return CoverTabRail(
      bounds: coverRail,
      child: Scaffold(
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
                      child: ExcludeSemantics(
                        excluding: screenIndex != index,
                        child: screens[screenIndex],
                      ),
                    ),
                  ),
              ],
            ),
            const BottomNav(),
          ],
        ),
      ),
    );
  }
}

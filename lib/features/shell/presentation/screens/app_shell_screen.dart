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
class AppShellScreen extends ConsumerStatefulWidget {
  const AppShellScreen({super.key});

  @override
  ConsumerState<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends ConsumerState<AppShellScreen> {
  var _walletSelectionRequest = 0;

  void _openWalletSelection() {
    setState(() => _walletSelectionRequest += 1);
    ref.read(appShellIndexProvider.notifier).setIndex(appShellSettingsTabIndex);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(appShellIndexProvider);
    final layout = ref.watch(duoDisplayLayoutProvider).value;
    final isDuoCover =
        layout != null &&
        layout.isCover &&
        layout.appliesTo(MediaQuery.sizeOf(context));

    final screens = <Widget>[
      HomeScreen(
        onOpenWalletSelection: context.fitsDuoLandscapePanes
            ? _openWalletSelection
            : null,
      ),
      const ScanScreen(purpose: ScanPurpose.sendLauncher),
      MarketScreen(isDuoCover: isDuoCover),
      SettingsScreen(
        isActiveTab: index == appShellSettingsTabIndex,
        walletSelectionRequest: _walletSelectionRequest,
      ),
    ];
    final rail = CoverTabRail.resolve(context, layout, appShellTabCount);

    return CoverTabRail(
      bounds: rail,
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

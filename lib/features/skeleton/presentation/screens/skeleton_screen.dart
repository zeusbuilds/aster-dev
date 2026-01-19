import 'package:aster/features/home/presentation/screens/home_screen.dart';
import 'package:aster/features/market/presentation/screens/market_screen.dart';
import 'package:aster/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/bottom_nav.dart';
import '../providers/skeleton_index_provider.dart';

/// Main skeleton screen containing bottom navigation and screen stack
///
/// Manages navigation between home, cards, settings, and other screens
class SkeletonScreen extends ConsumerWidget {
  const SkeletonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(skeletonIndexProvider);

    final screens = <Widget>[
      const HomeScreen(),
      const Center(child: Text('Card Screen')),
      const MarketScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          // Use IndexedStack so that all screens stay mounted
          IndexedStack(index: index, children: screens),
          const BottomNav(),
        ],
      ),
    );
  }
}

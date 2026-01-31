import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:aster/features/home/presentation/screens/home_screen.dart';
import 'package:aster/features/market/presentation/screens/market_screen.dart';
import 'package:aster/features/receive/presentation/screens/screens.dart';
import 'package:aster/features/scan/presentation/screens/screens.dart';
import 'package:aster/features/send/presentation/screens/screens.dart';
import 'package:aster/features/settings/presentation/screens/country_selection_screen.dart';
import 'package:aster/features/settings/presentation/screens/currency_selection_screen.dart';
import 'package:aster/features/settings/presentation/screens/settings_screen.dart';
import 'package:aster/features/skeleton/presentation/screens/skeleton_screen.dart';
import 'package:aster/features/swap/presentation/screens/swap_screen.dart';
import 'package:aster/features/transaction/presentation/screens/transaction_list_screen.dart';
import 'package:aster/features/wallet/presentation/pages/wallet_selection_screen.dart';
import '../screens/splash_screen.dart';
import 'route_names.dart';
import 'route_paths.dart';

/// Route configuration
class RouteConfig {
  RouteConfig._();

  /// Creates routes list
  static List<RouteBase> getRoutes() {
    return [
      GoRoute(
        path: RoutePaths.splash,
        name: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RoutePaths.skeleton,
        name: RouteNames.skeleton,
        builder: (context, state) => const SkeletonScreen(),
      ),
      GoRoute(
        path: RoutePaths.home,
        name: RouteNames.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: RoutePaths.send,
        name: RouteNames.send,
        builder: (context, state) => const SendScreen(),
      ),
      GoRoute(
        path: RoutePaths.sendAddress,
        name: RouteNames.sendAddress,
        builder: (context, state) => const SendAddressScreen(),
      ),
      GoRoute(
        path: RoutePaths.receive,
        name: RouteNames.receive,
        builder: (context, state) => const ReceiveScreen(),
      ),
      GoRoute(
        path: RoutePaths.receiveSetAmount,
        name: RouteNames.receiveSetAmount,
        builder: (context, state) => const ReceiveSetAmountScreen(),
      ),
      GoRoute(
        path: RoutePaths.swap,
        name: RouteNames.swap,
        builder: (context, state) => const SwapScreen(),
      ),
      GoRoute(
        path: RoutePaths.market,
        name: RouteNames.market,
        builder: (context, state) => const MarketScreen(),
      ),
      GoRoute(
        path: RoutePaths.transactionList,
        name: RouteNames.transactionList,
        builder: (context, state) => const TransactionListScreen(),
      ),
      GoRoute(
        path: RoutePaths.scan,
        name: RouteNames.scan,
        builder: (context, state) => const ScanScreen(),
      ),
      GoRoute(
        path: RoutePaths.settings,
        name: RouteNames.settings,
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: RoutePaths.walletSelection,
            name: RouteNames.walletSelection,
            builder: (context, state) => const WalletSelectionScreen(),
          ),
          GoRoute(
            path: RoutePaths.countrySelection,
            name: RouteNames.countrySelection,
            builder: (context, state) => const CountrySelectionScreen(),
          ),
          GoRoute(
            path: RoutePaths.currencySelection,
            name: RouteNames.currencySelection,
            builder: (context, state) => const CurrencySelectionScreen(),
          ),
        ],
      ),
      // GDK Test Screen (for development/testing)
    ];
  }
}

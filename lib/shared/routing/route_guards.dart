import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/wallet/presentation/models/models.dart';
import 'route_paths.dart';

/// Pure wallet-access redirect policy shared by GoRouter and unit tests.
abstract final class RouteGuards {
  /// Resolves access from durable wallet state before any feature is built.
  static String? redirect({
    required String location,
    required AsyncValue<WalletState> walletState,
  }) {
    final wallet = walletState.value;
    if (wallet == null) {
      return location == RoutePaths.splash ? null : RoutePaths.splash;
    }

    final onboarding = _isOnboarding(location);
    if (wallet.activeWallet == null) {
      return onboarding ? null : RoutePaths.onboardingWelcome;
    }
    if (location == RoutePaths.splash || onboarding) {
      return RoutePaths.home;
    }
    return null;
  }

  static bool _isOnboarding(String location) {
    return location == RoutePaths.onboardingWelcome ||
        location.startsWith('/onboarding/');
  }
}

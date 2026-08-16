import 'package:go_router/go_router.dart';

import '../../features/market/presentation/screens/screens.dart';
import '../../features/onboarding/presentation/screens/screens.dart';
import '../../features/receive/presentation/screens/screens.dart';
import '../../features/scan/domain/models/models.dart';
import '../../features/scan/presentation/screens/screens.dart';
import '../../features/send/presentation/screens/screens.dart';
import '../../features/settings/presentation/screens/screens.dart';
import '../../features/shell/presentation/screens/screens.dart';
import '../../features/swap/presentation/screens/screens.dart';
import '../../features/transaction/presentation/screens/screens.dart';
import '../../features/wallet/domain/models/models.dart';
import '../../features/wallet/presentation/pages/pages.dart';
import 'route_names.dart';
import 'route_paths.dart';

/// Builds the guarded wallet route graph and validates typed path segments.
abstract final class RouteConfig {
  RouteConfig._();

  /// Returns a fresh route graph for one [GoRouter] owner.
  static List<RouteBase> getRoutes() {
    return [
      GoRoute(
        path: RoutePaths.splash,
        name: RouteNames.splash,
        builder: (context, state) => const WalletAccessScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => OnboardingShell(child: child),
        routes: [
          GoRoute(
            path: RoutePaths.onboardingWelcome,
            name: RouteNames.onboardingWelcome,
            builder: (context, state) => const OnboardingWelcomeScreen(),
          ),
          GoRoute(
            path: RoutePaths.onboardingCreateWallet,
            name: RouteNames.onboardingCreateWallet,
            builder: (context, state) => const OnboardingCreateWalletScreen(),
          ),
          GoRoute(
            path: RoutePaths.onboardingImportWallet,
            name: RouteNames.onboardingImportWallet,
            builder: (context, state) => const OnboardingImportWalletScreen(),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.home,
        name: RouteNames.home,
        builder: (context, state) => const AppShellScreen(),
      ),
      GoRoute(
        path: RoutePaths.send,
        name: RouteNames.send,
        builder: (context, state) => const SendScreen(),
      ),
      GoRoute(
        path: RoutePaths.sendAddress,
        name: RouteNames.sendAddress,
        redirect: (context, state) =>
            _invalidPaymentTargetRedirect(state, fallback: RoutePaths.send),
        builder: (context, state) =>
            SendAddressScreen(target: _paymentTarget(state)),
      ),
      GoRoute(
        path: RoutePaths.sendAmount,
        name: RouteNames.sendAmount,
        redirect: (context, state) =>
            _invalidPaymentTargetRedirect(state, fallback: RoutePaths.send),
        builder: (context, state) =>
            SendAmountScreen(target: _paymentTarget(state)),
      ),
      GoRoute(
        path: RoutePaths.receive,
        name: RouteNames.receive,
        builder: (context, state) => const ReceiveScreen(),
      ),
      GoRoute(
        path: RoutePaths.receiveRequest,
        name: RouteNames.receiveRequest,
        redirect: (context, state) =>
            _invalidPaymentTargetRedirect(state, fallback: RoutePaths.receive),
        builder: (context, state) =>
            ReceiveRequestScreen(target: _paymentTarget(state)),
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
        redirect: (context, state) => _invalidActivityListRedirect(state),
        builder: (context, state) =>
            TransactionListScreen(assetKind: _assetKind(state)),
      ),
      GoRoute(
        path: RoutePaths.transactionDetails,
        name: RouteNames.transactionDetails,
        redirect: (context, state) => _invalidActivityDetailsRedirect(state),
        builder: (context, state) => TransactionDetailsScreen(
          assetKind: _assetKind(state),
          activityId: state.pathParameters[RoutePaths.activityIdParameter]!,
        ),
      ),
      GoRoute(
        path: RoutePaths.scan,
        name: RouteNames.scan,
        builder: (context, state) => ScanScreen(
          purpose: state.extra == ScanPurpose.destinationPicker
              ? ScanPurpose.destinationPicker
              : ScanPurpose.sendLauncher,
        ),
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
          GoRoute(
            path: RoutePaths.bitcoinUnitSelection,
            name: RouteNames.bitcoinUnitSelection,
            builder: (context, state) => const BitcoinUnitSelectionScreen(),
          ),
          GoRoute(
            path: RoutePaths.advancedSettings,
            name: RouteNames.advancedSettings,
            builder: (context, state) => const AdvancedSettingsScreen(),
            routes: [
              GoRoute(
                path: RoutePaths.networkConfiguration,
                name: RouteNames.networkConfiguration,
                builder: (context, state) => const NetworkConfigurationScreen(),
              ),
            ],
          ),
        ],
      ),
    ];
  }

  static WalletPaymentTarget _paymentTarget(GoRouterState state) {
    return WalletPaymentTarget.tryParse(
      state.pathParameters[RoutePaths.paymentTargetParameter],
    )!;
  }

  static WalletAssetKind _assetKind(GoRouterState state) {
    return WalletAssetKind.tryParse(
      state.pathParameters[RoutePaths.assetKindParameter],
    )!;
  }

  static String? _invalidActivityListRedirect(GoRouterState state) {
    return WalletAssetKind.tryParse(
              state.pathParameters[RoutePaths.assetKindParameter],
            ) ==
            null
        ? RoutePaths.home
        : null;
  }

  static String? _invalidActivityDetailsRedirect(GoRouterState state) {
    final kind = WalletAssetKind.tryParse(
      state.pathParameters[RoutePaths.assetKindParameter],
    );
    if (kind == null) return RoutePaths.home;
    final activityId = state.pathParameters[RoutePaths.activityIdParameter];
    return WalletActivity.isValidId(activityId)
        ? null
        : RoutePaths.transactionListFor(kind.slug);
  }

  static String? _invalidPaymentTargetRedirect(
    GoRouterState state, {
    required String fallback,
  }) {
    return WalletPaymentTarget.tryParse(
              state.pathParameters[RoutePaths.paymentTargetParameter],
            ) ==
            null
        ? fallback
        : null;
  }
}

/// Canonical application locations and typed path builders.
class RoutePaths {
  RoutePaths._();

  // Wallet access and onboarding.
  static const String splash = '/';
  static const String onboardingWelcome = '/onboarding-welcome';

  // Guarded wallet application.
  static const String home = '/home';
  static const String send = '/send';
  static const String paymentTargetParameter = 'paymentTarget';
  static const String sendAddress = '/send/:paymentTarget/address';
  static const String sendAmount = '/send/:paymentTarget/amount';
  static const String receive = '/receive';
  static const String receiveRequest = '/receive/:paymentTarget';
  static const String swap = '/swap';
  static const String assetKindParameter = 'assetKind';
  static const String activityIdParameter = 'activityId';
  static const String transactionList = '/transactions/:assetKind';
  static const String transactionDetails =
      '/transactions/:assetKind/:activityId';
  static const String settings = '/settings';
  static const String walletDetails = 'wallet-details';
  static const String scan = '/scan';
  static const String walletSelection = 'wallet-selection';
  static const String addWallet = 'add-wallet';
  static const String countrySelection = 'country-selection';
  static const String currencySelection = 'currency-selection';
  static const String bitcoinUnitSelection = 'bitcoin-unit-selection';
  static const String security = 'security';
  static const String revealSeed = 'reveal-seed';
  static const String exportXpubs = 'export-xpubs';
  static const String advancedSettings = 'advanced';
  static const String networkConfiguration = 'network-configuration';
  static const String hostedBridge = 'dev-bridge';

  /// Concrete parent location for nested Advanced Settings routes.
  static const String advancedSettingsLocation = '$settings/$advancedSettings';

  /// Concrete location for selecting the active wallet from Settings.
  static const String walletSelectionLocation = '$settings/$walletSelection';

  /// Concrete location for creating or importing an additional wallet.
  static const String addWalletLocation = '$walletSelectionLocation/$addWallet';

  /// Concrete Send destination location for a validated payment-target slug.
  static String sendAddressFor(String paymentTarget) {
    return '$send/${Uri.encodeComponent(paymentTarget)}/address';
  }

  /// Concrete Activity-list location for a validated asset-kind slug.
  static String transactionListFor(String assetKind) {
    return '/transactions/${Uri.encodeComponent(assetKind)}';
  }
}

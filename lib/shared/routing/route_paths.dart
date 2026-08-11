/// Route path constants
class RoutePaths {
  RoutePaths._();

  // Splash & Auth
  static const String splash = '/';
  static const String onboardingWelcome = '/onboarding-welcome';
  static const String onboardingCreateWallet = '/onboarding/create-wallet';
  static const String onboardingImportWallet = '/onboarding/import-wallet';

  // Main
  static const String skeleton = '/skeleton';
  static const String home = '/home';
  static const String send = '/send';
  static const String paymentTargetParameter = 'paymentTarget';
  static const String sendAddress = '/send/:paymentTarget/address';
  static const String sendAmount = '/send/:paymentTarget/amount';
  static const String receive = '/receive';
  static const String receiveRequest = '/receive/:paymentTarget';
  static const String swap = '/swap';
  static const String market = '/market';
  static const String assetKindParameter = 'assetKind';
  static const String activityIdParameter = 'activityId';
  static const String transactionList = '/transactions/:assetKind';
  static const String transactionDetails =
      '/transactions/:assetKind/:activityId';
  static const String settings = '/settings';
  static const String scan = '/scan';
  static const String walletSelection = 'wallet-selection';
  static const String countrySelection = 'country-selection';
  static const String currencySelection = 'currency-selection';
  static const String bitcoinUnitSelection = 'bitcoin-unit-selection';
  static const String advancedSettings = 'advanced';
  static const String networkConfiguration = 'network-configuration';
}

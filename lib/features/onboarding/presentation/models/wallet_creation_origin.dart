/// Entry point that owns cancellation and completion routing for wallet setup.
enum WalletCreationOrigin {
  /// First wallet created from the branded onboarding welcome screen.
  onboarding,

  /// Additional wallet created from the guarded wallet selector.
  walletSelector,
}

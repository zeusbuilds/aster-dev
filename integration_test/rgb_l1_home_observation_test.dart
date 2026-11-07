import 'full_wallet_flow_test.dart' as campaign;

/// Existing completed QA storage only. Normal Home refresh is allowed, so this
/// is separate from the genuine no-refresh cold-process qualification branch.
void main() => campaign.runFullWalletFlowQualification(
  qualifyLocalRgbL1: true,
  observeCompletedHome: true,
);

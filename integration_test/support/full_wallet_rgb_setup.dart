import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/models/models.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'full_wallet_qa.dart';
import 'full_wallet_test_guard.dart';

/// The existing host's full campaign seeds BFA through a blind-only bridge.
/// Aster now generates witness invoices exclusively. Reject the incompatible
/// campaign before opening QA storage, creating a wallet or requesting funds.
/// Lifecycle and historical read-only reconciliation remain usable. Re-enabling
/// full qualification requires a separately owned bridge receiver followed by a
/// real issuer-to-Aster witness transfer, and corresponding host verification.
void requireQaSupportedFundingStage(String stage) {
  if (stage == 'full') {
    throw const FullWalletQaFailure(
      'qa_bridge_mint_requires_external_blind_receiver',
    );
  }
}

/// Uses the ordinary Receive screen. No allocation preparation or extra Bitcoin
/// transaction is necessary to create the receiver's witness invoice.
Future<WalletReceiveRequest> qualifyRgbReceiveUi({
  required WidgetTester tester,
  required ProviderContainer container,
  required WalletRepository repository,
  required FullWalletQaControl control,
}) async {
  const target = WalletPaymentTarget.usdtOnchain;
  container.read(appRouterProvider).go('/receive/${target.slug}');
  await qualifyWitnessReceiveUi(
    tester,
    isRequestReady: () {
      final current = container.read(receiveFlowViewModelProvider(target));
      if (current case AsyncError(:final error, :final stackTrace)) {
        throw qaAppFailure(
          'witness_receive',
          FailureMapper.from(error, stackTrace),
        );
      }
      return qaWitnessReceiveReady(current);
    },
  );
  if (find.text('Use blind receive').evaluate().isNotEmpty ||
      find.text('Use witness receive').evaluate().isNotEmpty ||
      find.text('Prepare wallet').evaluate().isNotEmpty) {
    throw const FullWalletQaFailure('qa_receive_exposes_removed_mode');
  }
  final request = container
      .read(receiveFlowViewModelProvider(target))
      .value!
      .request!;
  requireQaWitnessPreview(
    requireQaSuccess(
      await repository.previewPayment(target, request.encodedRequest),
      'witness_receive_preview',
    ),
  );
  final current = container.read(receiveFlowViewModelProvider(target));
  if (!qaWitnessReceiveReady(current) ||
      current.value?.request?.encodedRequest != request.encodedRequest) {
    throw const FullWalletQaFailure('qa_witness_invoice_changed');
  }
  await control.event('witness_receive_created', {
    'recipient_bitcoin_sats': rgbWitnessRecipientSats,
  });
  return request;
}

/// Read-only wait: a slow invoice reservation must not trigger another request,
/// setup confirmation, mode switch or financial command.
Future<void> qualifyWitnessReceiveUi(
  WidgetTester tester, {
  required bool Function() isRequestReady,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    requireQaFrameworkHealthy(tester);
    if (isRequestReady()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw const FullWalletQaFailure('qa_witness_request_timeout');
}

bool qaWitnessReceiveReady(AsyncValue<ReceiveFlowState> state) =>
    state is AsyncData<ReceiveFlowState> &&
    !state.isLoading &&
    !state.value.isBusy &&
    !state.value.isExpiredAt(DateTime.now().toUtc()) &&
    state.value.route.target == WalletPaymentTarget.usdtOnchain &&
    state.value.request?.route.target == WalletPaymentTarget.usdtOnchain;

void requireQaWitnessPreview(WalletPaymentPreview preview) {
  if (preview.route.target != WalletPaymentTarget.usdtOnchain ||
      preview.rgbRecipientType != RgbRecipientType.witness ||
      preview.witnessBitcoinAmountSats != rgbWitnessRecipientSats) {
    throw const FullWalletQaFailure('qa_receive_invoice_not_witness');
  }
}

/// Historical checkpoints may contain blind invoices from earlier campaigns.
/// Decoding an existing invoice never creates a new blind receive reservation.
void requireQaBlindPreview(WalletPaymentPreview preview) {
  if (preview.route.target != WalletPaymentTarget.usdtOnchain ||
      preview.rgbRecipientType != RgbRecipientType.blind ||
      preview.witnessBitcoinAmountSats != null) {
    throw const FullWalletQaFailure('qa_checkpoint_invoice_not_blind');
  }
}

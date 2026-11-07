import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'full_wallet_qa.dart';
import 'full_wallet_rgb_setup.dart';
import 'full_wallet_send_ui.dart';
import 'full_wallet_test_guard.dart';

/// Explicit integration entrypoint admission; no normal app flag calls this.
WalletServiceConfiguration requireLocalRgbL1Services(
  WalletServiceConfiguration services, {
  bool requireUsdt = false,
}) {
  if (!kDebugMode ||
      services.backend != WalletBackend.rgbL1 ||
      services.environment != BlockchainEnvironment.regtest ||
      services.signetDeployment != SignetDeployment.publicBitcoin ||
      services.indexerUrl == null ||
      services.rgbTransportProxy == null ||
      (requireUsdt && services.usdtAsset?.canonicalContract == null) ||
      services.vssUrl != null ||
      services.lspBaseUrl != null) {
    throw const FullWalletQaFailure('qa_local_l1_profile_required');
  }
  services.validate();
  for (final endpoint in [
    services.indexerUrl,
    services.rgbTransportProxy,
    if (services.ethRpcUrl != null) services.ethRpcUrl,
  ]) {
    if (endpoint == null ||
        !{
          '127.0.0.1',
          '::1',
          'localhost',
        }.contains(Uri.tryParse(endpoint)?.host.toLowerCase())) {
      throw const FullWalletQaFailure('qa_local_l1_loopback_required');
    }
  }
  return services;
}

/// Uses existing fixture funds through public-only coordinated requests. The
/// controller must journal each host mutation before acknowledging it. A lost
/// acknowledgement stops the campaign; none of the requests or sends retries.
Future<void> qualifyLocalRgbL1FundedFlows({
  required WidgetTester tester,
  required ProviderContainer container,
  required WalletRepository repository,
  required FullWalletQaControl control,
  String? retainedBtcDestination,
}) async {
  requireLocalRgbL1Services(
    container.read(walletServiceConfigurationProvider),
    requireUsdt: true,
  );
  final Object? btcDestination;
  if (retainedBtcDestination != null) {
    // The dedicated continuation entrypoint has already authenticated an
    // untouched, funded pre-send checkpoint. It never requests funding twice.
    btcDestination = retainedBtcDestination;
  } else {
    final address = requireQaSuccess(
      await repository.createReceiveRequest(WalletPaymentTarget.bitcoinOnchain),
      'l1_btc_receive',
    );
    final funding = await control.request('fund_requested', {
      'address': address.displayValue,
      'amount_sats': 100000,
    });
    btcDestination = funding['btc_send_address'];
  }
  if (btcDestination is! String) {
    throw const FullWalletQaFailure('qa_l1_btc_destination_missing');
  }
  await _wait(tester, () async {
    requireQaSuccess(await repository.sync(), 'l1_btc_funding_sync');
    final value = requireQaSuccess(
      await repository.balance(WalletAssetKind.bitcoin),
      'l1_btc_funding_balance',
    );
    return value.onchainSettled.units == 100000 &&
        value.onchainSpendable.units == 100000;
  });
  final btc = await qualifySendUi(
    tester: tester,
    container: container,
    repository: repository,
    control: control,
    target: WalletPaymentTarget.bitcoinOnchain,
    destination: btcDestination,
    amountUnits: 1000,
  );
  await control.request('btc_confirm_requested', {
    'txid': btc.referenceId,
    'recipient': btcDestination,
    'amount_sats': 1000,
  });
  await _confirmed(
    tester,
    repository,
    WalletAssetKind.bitcoin,
    btc.referenceId,
    1000,
  );
  await control.event('l1_btc_send_confirmed', {'txid': btc.referenceId});

  final receive = await qualifyRgbReceiveUi(
    tester: tester,
    container: container,
    repository: repository,
    control: control,
  );
  final incoming = await control.request('rgb_witness_funding_requested', {
    'invoice': receive.encodedRequest,
    'amount_units': 100,
    'return_amount_units': 50,
  });
  final invoice = incoming['return_invoice'];
  if (invoice is! String) {
    throw const FullWalletQaFailure('qa_l1_return_invoice_missing');
  }
  await qualifyLocalRgbL1ReturnFlow(
    tester: tester,
    container: container,
    repository: repository,
    control: control,
    invoice: invoice,
    confirmedBtcTxid: btc.referenceId,
    receivedRgbTxid: incoming['incoming_txid'] as String?,
    requireUnconfirmedEvidence: true,
  );
}

/// Continues an intact, explicitly verified received-asset checkpoint. No BTC
/// send, new receive reservation or funding request is made by this function.
Future<void> qualifyLocalRgbL1ReturnFlow({
  required WidgetTester tester,
  required ProviderContainer container,
  required WalletRepository repository,
  required FullWalletQaControl control,
  required String invoice,
  required String confirmedBtcTxid,
  String? receivedRgbTxid,
  bool requireUnconfirmedEvidence = false,
}) async {
  if (requireUnconfirmedEvidence &&
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(receivedRgbTxid ?? '')) {
    throw const FullWalletQaFailure('qa_incoming_transaction_identity_missing');
  }
  await _confirmed(
    tester,
    repository,
    WalletAssetKind.bitcoin,
    confirmedBtcTxid,
    1000,
  );
  var observedUnconfirmed = false;
  final preview = requireQaSuccess(
    await repository.previewPayment(WalletPaymentTarget.usdtOnchain, invoice),
    'l1_return_invoice',
  );
  requireQaWitnessPreview(preview);
  if (preview.amount?.units != 50) {
    throw const FullWalletQaFailure('qa_l1_return_amount_not_bound');
  }
  await _wait(tester, () async {
    requireQaSuccess(await repository.sync(), 'l1_rgb_funding_sync');
    final value = requireQaSuccess(
      await repository.balance(WalletAssetKind.usdt),
      'l1_rgb_funding_balance',
    );
    if (requireUnconfirmedEvidence &&
        !observedUnconfirmed &&
        value.onchainFuture.units == 100 &&
        value.onchainSettled.units == 0 &&
        value.onchainSpendable.units == 0) {
      final feed = requireQaSuccess(
        await repository.activityFeed(WalletAssetKind.usdt),
        'l1_unconfirmed_receive_history',
      );
      final rows = feed.activities
          .where(
            (row) =>
                row.txid == receivedRgbTxid &&
                row.direction == WalletActivityDirection.received &&
                row.amount?.units == 100,
          )
          .toList();
      if (rows.length == 1 &&
          rows.single.status == WalletActivityStatus.waitingConfirmations) {
        observedUnconfirmed = true;
        await control.event('l1_rgb_unconfirmed_pending_observed', {
          'txid': receivedRgbTxid,
          'future_units': 100,
          'settled_units': 0,
          'spendable_units': 0,
          'history_status': rows.single.status.name,
          'requested_min_confirmations': 1,
        });
      }
    }
    return value.onchainSettled.units == 100 &&
        value.onchainSpendable.units == 100;
  });
  if (requireUnconfirmedEvidence && !observedUnconfirmed) {
    throw const FullWalletQaFailure(
      'qa_receive_confirmation_policy_not_observed',
    );
  }
  if (receivedRgbTxid != null) {
    final feed = requireQaSuccess(
      await repository.activityFeed(WalletAssetKind.usdt),
      'l1_confirmed_receive_history',
    );
    final rows = feed.activities
        .where(
          (row) =>
              row.txid == receivedRgbTxid &&
              row.direction == WalletActivityDirection.received &&
              row.amount?.units == 100,
        )
        .toList();
    if (rows.length != 1 ||
        rows.single.status != WalletActivityStatus.succeeded) {
      throw const FullWalletQaFailure('qa_confirmed_receive_history_mismatch');
    }
  }
  final result = await qualifySendUi(
    tester: tester,
    container: container,
    repository: repository,
    control: control,
    target: WalletPaymentTarget.usdtOnchain,
    destination: invoice,
    amountUnits: 50,
    prepareRgbChangeOutputs: true,
  );
  await control.request('btc_confirm_requested', {
    'txid': result.referenceId,
    'asset_id': result.route.asset.id.value,
    'recipient_invoice': invoice,
    'amount_units': 50,
  });
  await _confirmed(
    tester,
    repository,
    WalletAssetKind.usdt,
    result.referenceId,
    50,
  );
  final remaining = requireQaSuccess(
    await repository.balance(WalletAssetKind.usdt),
    'l1_rgb_remaining',
  );
  if (remaining.onchainSettled.units != 50 ||
      remaining.onchainSpendable.units != 50) {
    throw const FullWalletQaFailure('qa_l1_remaining_balance_changed');
  }
  final pending = requireQaSuccess(
    await repository.paymentSubmissionStatus(),
    'l1_payment_receipt',
  );
  if (pending != null && pending.requiresReconciliation) {
    throw const FullWalletQaFailure('qa_l1_payment_still_fenced');
  }
  await control.event('l1_full_funded_flow_passed', {
    'btc_txid': confirmedBtcTxid,
    'rgb_txid': result.referenceId,
    'remaining_units': 50,
  });
}

Future<void> _confirmed(
  WidgetTester tester,
  WalletRepository repository,
  WalletAssetKind asset,
  String txid,
  int amount,
) => _wait(tester, () async {
  requireQaSuccess(await repository.sync(), 'l1_confirmation_sync');
  final feed = requireQaSuccess(
    await repository.activityFeed(asset),
    'l1_history',
  );
  final matching = feed.activities
      .where(
        (row) =>
            row.txid == txid && row.direction == WalletActivityDirection.sent,
      )
      .toList();
  return matching.length == 1 &&
      matching.single.amount?.units == amount &&
      matching.single.status == WalletActivityStatus.succeeded;
});

Future<void> _wait(WidgetTester tester, Future<bool> Function() ready) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (DateTime.now().isBefore(deadline)) {
    requireQaFrameworkHealthy(tester);
    if (await ready()) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  throw const FullWalletQaFailure('qa_l1_observation_timeout');
}

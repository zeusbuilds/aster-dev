import 'dart:async';

import 'package:aster/features/onboarding/presentation/view_model/view_models.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/pages/wallet_selection_screen.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'full_wallet_qa.dart';
import 'full_wallet_rgb_setup.dart';
import 'full_wallet_send_ui.dart';
import 'full_wallet_test_guard.dart';

/// Full app-owned import, selection, BFA transfer and funded reopen acceptance.
/// Two fresh profiles use independent native stores in the same QA namespace.
Future<void> qualifyImportedWalletTransfer({
  required WidgetTester tester,
  required ProviderContainer container,
  required WalletRepository repository,
  required FullWalletQaControl control,
  required void Function(bool active) sensitiveScreenChanged,
}) async {
  final originalRegistry = requireQaSuccess(
    await repository.load(),
    'original_registry',
  );
  final original = originalRegistry.activeProfile;
  if (original == null || originalRegistry.readyProfiles.length != 1) {
    throw const FullWalletQaFailure('qa_original_wallet_missing');
  }
  final originalIdentity = requireQaSuccess(
    await repository.networkStatus(),
    'original_identity',
  );
  // The actual SDK generates the import phrase. Only this UI input scope owns
  // it; no clipboard, fixed mnemonic, host export or screenshot is involved.
  final importPhrase = requireQaSuccess(
    await repository.generateMnemonic(),
    'import_phrase_generation',
  );
  container.read(appRouterProvider).go(RoutePaths.addWalletLocation);
  await _untilUi(
    tester,
    () => find
        .widgetWithText(CustomButton, 'Add New Wallet')
        .evaluate()
        .isNotEmpty,
  );
  await control.event('secret_screen_active');
  sensitiveScreenChanged(true);
  await _tap(
    tester,
    find.bySemanticsLabel('Import Wallet'),
    failureCode: 'qa_import_open',
  );
  await control.event('onboarding_import_action_tapped');
  final firstWord = find.byKey(const ValueKey('recovery-word-1'));
  await _untilUi(
    tester,
    () => firstWord.evaluate().length == 1,
    failureCode: 'qa_import_fields_missing',
  );
  await control.event('onboarding_import_fields_ready');
  await tester.ensureVisible(firstWord);
  await tester.enterText(firstWord, importPhrase);
  await control.event('onboarding_import_input_entered');
  await _untilUi(tester, () {
    final state = container.read(importWalletViewModelProvider).value;
    if (state?.failure case final failure?) {
      throw qaAppFailure('import_validation', failure);
    }
    return state?.canContinue == true;
  });
  await control.event('onboarding_import_validation_passed');
  await qualifyImportContinueUi(tester);
  await control.event('onboarding_import_continue_tapped');
  final nameField = find.byKey(const ValueKey('wallet-name-field'));
  await _untilUi(tester, () => nameField.evaluate().length == 1);
  await control.event('onboarding_import_name_opened');
  await tester.enterText(nameField, 'Imported QA ${control.role}');
  await _untilUi(
    tester,
    () =>
        container.read(importWalletViewModelProvider).value?.canSubmit == true,
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 300));
  await control.event('onboarding_import_submit_requested');
  await _tap(tester, find.widgetWithText(CustomButton, 'Import Wallet'));
  await _untilUi(tester, () {
    final state = container.read(importWalletViewModelProvider).value;
    if (state?.failure case final failure?) {
      throw qaAppFailure('import_provision', failure);
    }
    final active = container.read(walletViewModelProvider).value?.activeWallet;
    return active != null && active.id != original.id;
  });
  await tester.pump(const Duration(milliseconds: 500));
  await control.event('secret_screen_cleared');
  sensitiveScreenChanged(false);
  final importedRegistry = requireQaSuccess(
    await repository.load(),
    'imported_registry',
  );
  final imported = importedRegistry.activeProfile;
  final importedIdentity = requireQaSuccess(
    await repository.networkStatus(),
    'imported_identity',
  );
  if (imported == null ||
      importedRegistry.readyProfiles.length != 2 ||
      imported.id == original.id ||
      importedIdentity.nodePublicKey == originalIdentity.nodePublicKey) {
    throw const FullWalletQaFailure('qa_import_identity_invalid');
  }
  final importedZero = await _snapshot(repository);
  if (importedZero['btc_settled_sats'] != 0 ||
      importedZero['bfa_settled_units'] != 0) {
    throw const FullWalletQaFailure('qa_imported_wallet_not_zero');
  }
  await control.event('import_passed', importedZero);
  final receive = requireQaSuccess(
    await repository.createReceiveRequest(WalletPaymentTarget.bitcoinOnchain),
    'imported_btc_receive',
  );
  await control.request('fund_requested', {
    'address': receive.displayValue,
    'amount_sats': 2000000,
  });
  await _untilWallet(tester, () async {
    requireQaSuccess(await repository.sync(), 'imported_funding_sync');
    final balance = requireQaSuccess(
      await repository.balance(WalletAssetKind.bitcoin),
      'imported_funding_balance',
    );
    return balance.onchainSettled.units == 2000000 &&
        balance.onchainSpendable.units == 2000000;
  });
  final invoice = await qualifyRgbReceiveUi(
    tester: tester,
    container: container,
    repository: repository,
    control: control,
  );
  if (invoice.amount != null) {
    throw const FullWalletQaFailure('qa_first_invoice_unexpected_amount');
  }
  await control.event('imported_receive_prepared', {
    'invoice': invoice.encodedRequest,
    'amount_units': 1000000,
    'invoice_amount_bound': false,
  });
  await _switchUi(tester, container, original.id);
  final switchedIdentity = requireQaSuccess(
    await repository.networkStatus(),
    'switch_original_identity',
  );
  if (switchedIdentity.nodePublicKey != originalIdentity.nodePublicKey) {
    throw const FullWalletQaFailure('qa_switch_original_identity_changed');
  }
  final originalBalance = requireQaSuccess(
    await repository.balance(WalletAssetKind.usdt),
    'original_bfa_before_send',
  );
  if (originalBalance.onchainSettled.units != 5000000) {
    throw const FullWalletQaFailure('qa_original_bfa_balance_changed');
  }
  final preview = requireQaSuccess(
    await repository.previewPayment(
      WalletPaymentTarget.usdtOnchain,
      invoice.encodedRequest,
    ),
    'bfa_transfer_preview',
  );
  requireQaWitnessPreview(preview);
  if (preview.amount != null) {
    throw const FullWalletQaFailure(
      'qa_first_invoice_preview_unexpected_amount',
    );
  }
  // No retry is permitted after this mutation call. Subsequent reads reconcile
  // its durable native state even if a response or acknowledgement is lost.
  final sent = await qualifySendUi(
    tester: tester,
    container: container,
    repository: repository,
    control: control,
    target: WalletPaymentTarget.usdtOnchain,
    destination: invoice.encodedRequest,
    amountUnits: 1000000,
  );
  await control.event('bfa_transfer_submitted', {
    'txid': sent.referenceId,
    'amount_units': 1000000,
  });
  await qualifyExistingTransferPair(
    tester: tester,
    repository: repository,
    senderId: original.id,
    senderPublicKey: originalIdentity.nodePublicKey,
    receiverId: imported.id,
    receiverPublicKey: importedIdentity.nodePublicKey,
    txid: sent.referenceId,
    amountUnits: 1000000,
    senderUnits: 4000000,
    receiverUnits: 1000000,
  );
  await _switchUi(tester, container, imported.id);
  final receivedFeed = requireQaSuccess(
    await repository.activityFeed(WalletAssetKind.usdt),
    'imported_bfa_history',
  );
  _requireSingleTransfer(
    receivedFeed,
    sent.referenceId,
    WalletActivityDirection.received,
  );
  await control.event('bfa_transfer_received', {
    'txid': sent.referenceId,
    ...await _snapshot(repository),
  });
  await _switchUi(tester, container, original.id);
  final sentFeed = requireQaSuccess(
    await repository.activityFeed(WalletAssetKind.usdt),
    'original_bfa_history',
  );
  _requireSingleTransfer(
    sentFeed,
    sent.referenceId,
    WalletActivityDirection.sent,
  );
  await control.event('bfa_pair_conservation_passed', {
    'txid': sent.referenceId,
    'original_units': 4000000,
    'imported_units': 1000000,
    'total_units': 5000000,
  });
  // Exercise the ordinary witness route in both directions. The additional
  // Bitcoin output must be visible before the second transfer is submitted.
  final originalBtc = requireQaSuccess(
    await repository.balance(WalletAssetKind.bitcoin),
    'before_witness_bitcoin',
  );
  const rgbTarget = WalletPaymentTarget.usdtOnchain;
  container.read(appRouterProvider).go('/receive/${rgbTarget.slug}');
  await _untilUi(
    tester,
    () =>
        container
            .read(receiveFlowViewModelProvider(rgbTarget))
            .value
            ?.request !=
        null,
  );
  final witnessRequest = container
      .read(receiveFlowViewModelProvider(rgbTarget))
      .value!
      .request!;
  final witnessPreview = requireQaSuccess(
    await repository.previewPayment(rgbTarget, witnessRequest.encodedRequest),
    'witness_receive_preview',
  );
  if (witnessPreview.rgbRecipientType != RgbRecipientType.witness ||
      witnessPreview.witnessBitcoinAmountSats != rgbWitnessRecipientSats) {
    throw const FullWalletQaFailure('qa_default_receive_not_witness');
  }
  await control.event('default_witness_receive_passed');
  await _switchUi(tester, container, imported.id);
  final witnessSent = await qualifySendUi(
    tester: tester,
    container: container,
    repository: repository,
    control: control,
    target: rgbTarget,
    destination: witnessRequest.encodedRequest,
    amountUnits: 100000,
  );
  await qualifyExistingTransferPair(
    tester: tester,
    repository: repository,
    senderId: imported.id,
    senderPublicKey: importedIdentity.nodePublicKey,
    receiverId: original.id,
    receiverPublicKey: originalIdentity.nodePublicKey,
    txid: witnessSent.referenceId,
    amountUnits: 100000,
    senderUnits: 900000,
    receiverUnits: 4100000,
  );
  await _switchUi(tester, container, original.id);
  final witnessBtc = requireQaSuccess(
    await repository.balance(WalletAssetKind.bitcoin),
    'witness_recipient_bitcoin',
  );
  if (witnessBtc.onchainSettled.units !=
      originalBtc.onchainSettled.units + rgbWitnessRecipientSats) {
    throw const FullWalletQaFailure('qa_witness_bitcoin_output_not_received');
  }
  _requireSingleTransfer(
    requireQaSuccess(
      await repository.activityFeed(WalletAssetKind.usdt),
      'witness_receive_history',
    ),
    witnessSent.referenceId,
    WalletActivityDirection.received,
    units: 100000,
  );
  await _switchUi(tester, container, imported.id);
  _requireSingleTransfer(
    requireQaSuccess(
      await repository.activityFeed(WalletAssetKind.usdt),
      'witness_send_history',
    ),
    witnessSent.referenceId,
    WalletActivityDirection.sent,
    units: 100000,
  );
  await control.event('witness_pair_conservation_passed', {
    'txid': witnessSent.referenceId,
    'original_units': 4100000,
    'imported_units': 900000,
    'total_units': 5000000,
    'recipient_bitcoin_sats': rgbWitnessRecipientSats,
  });
  await _switchUi(tester, container, original.id);
  for (var cycle = 1; cycle <= 3; cycle += 1) {
    requireQaSuccess(await repository.suspend(), 'funded_suspend_$cycle');
    requireQaSuccess(await repository.resume(), 'funded_resume_$cycle');
    final balance = requireQaSuccess(
      await repository.balance(WalletAssetKind.usdt),
      'funded_reopen_balance',
    );
    if (balance.onchainSettled.units != 4100000) {
      throw const FullWalletQaFailure('qa_funded_reopen_balance_changed');
    }
  }
  await control.event('funded_lifecycle_passed', await _snapshot(repository));
}

void _requireSingleTransfer(
  WalletActivityFeed feed,
  String txid,
  WalletActivityDirection direction, {
  int units = 1000000,
}) {
  final matches = feed.activities
      .where((item) => item.txid == txid && item.direction == direction)
      .toList();
  if (matches.length != 1 ||
      matches.single.status != WalletActivityStatus.succeeded ||
      matches.single.amount?.units != units) {
    throw const FullWalletQaFailure('qa_bfa_history_not_unique_and_settled');
  }
}

Future<void> _switchUi(
  WidgetTester tester,
  ProviderContainer container,
  String walletId,
) async {
  await qualifyWalletSelectionUi(
    tester: tester,
    router: container.read(appRouterProvider),
    walletRow: find.byKey(ValueKey('wallet-$walletId')),
    selector: find.byType(WalletSelectionScreen),
    committed: () {
      final state = container.read(walletViewModelProvider);
      if (state.value?.operationFailure case final failure?) {
        throw qaAppFailure('wallet_switch', failure);
      }
      return state.value?.activeWallet?.id == walletId &&
          state.value?.switchingWalletId == null;
    },
  );
}

/// Selection publishes its committed wallet before its UI confirmation delay
/// and pop complete. Keep ownership of that pushed route until it has actually
/// closed; a later Send must never replace a still-running selector callback.
/// Its original push future is observed for errors, not used as a pop signal:
/// GoRouter refresh reconstruction does not preserve that future.
Future<void> qualifyWalletSelectionUi({
  required WidgetTester tester,
  required GoRouter router,
  required Finder walletRow,
  required Finder selector,
  required bool Function() committed,
}) async {
  var routeFailed = false;
  unawaited(
    pushQaWalletSelector(router).then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        routeFailed = true;
      },
    ),
  );
  await _untilUi(tester, () => selector.evaluate().length == 1);
  final ownedRoute = ModalRoute.of(tester.element(selector));
  if (ownedRoute == null || !ownedRoute.isCurrent) {
    throw const FullWalletQaFailure('qa_wallet_selection_route_not_owned');
  }
  await _tap(tester, walletRow);
  await _untilUi(tester, () {
    if (routeFailed) {
      throw const FullWalletQaFailure('qa_wallet_selection_route_failed');
    }
    // GoRouter refresh can replace an imperative push completer. Observe the
    // exact ModalRoute removed by the selector callback, including its exit
    // animation, instead of waiting on that abandoned Future.
    return !ownedRoute.isActive && selector.evaluate().isEmpty && committed();
  });
  requireQaFrameworkHealthy(tester);
}

Future<void> pushQaWalletSelector(GoRouter router) =>
    router.push<void>(RoutePaths.walletSelectionLocation);

/// Progress only an already submitted transfer. Aster owns one native wallet at
/// a time: receiver refresh ACKs the consignment; sender refresh observes that
/// ACK and broadcasts the existing signed transaction. Neither may be omitted.
/// No invoice, funding, send, allocation setup or host mutation is invoked here.
Future<void> qualifyExistingTransferPair({
  required WidgetTester tester,
  required WalletRepository repository,
  required String senderId,
  required String senderPublicKey,
  required String receiverId,
  required String receiverPublicKey,
  required String txid,
  required int amountUnits,
  required int senderUnits,
  required int receiverUnits,
  bool requireExistingCheckpoint = false,
}) async {
  final registry = requireQaSuccess(await repository.load(), 'peer_registry');
  final activeId = registry.activeWalletId;
  final ids = {senderId, receiverId};
  if (ids.length != 2 ||
      senderPublicKey == receiverPublicKey ||
      registry.profiles.length != 2 ||
      registry.readyProfiles
          .map((profile) => profile.id)
          .toSet()
          .difference(ids)
          .isNotEmpty ||
      registry.readyProfiles.length != 2 ||
      activeId == null ||
      !ids.contains(activeId)) {
    throw const FullWalletQaFailure('qa_transfer_pair_registry_changed');
  }
  try {
    if (requireExistingCheckpoint) {
      // Bind the durable original outgoing transaction before any refresh can
      // observe ACK and broadcast it. Receiver pending history can omit a txid
      // before it has consumed the consignment, so it is checked after refresh.
      requireQaSuccess(
        await repository.switchWallet(senderId),
        'peer_checkpoint_select',
      );
      final identity = requireQaSuccess(
        await repository.networkStatus(),
        'peer_checkpoint_identity',
      );
      final feed = requireQaSuccess(
        await repository.activityFeed(WalletAssetKind.usdt),
        'peer_checkpoint_history',
      );
      final matches = feed.activities
          .where((item) => item.txid == txid)
          .toList();
      requireQaOriginalTransferCheckpoint(
        identityMatches: identity.nodePublicKey == senderPublicKey,
        matches: matches,
        amountUnits: amountUnits,
      );
    }
    await _untilWallet(tester, () async {
      var settled = true;
      // Receiver first publishes ACK; sender then sees it and may broadcast.
      for (final peer in [
        (
          receiverId,
          receiverPublicKey,
          receiverUnits,
          WalletActivityDirection.received,
        ),
        (senderId, senderPublicKey, senderUnits, WalletActivityDirection.sent),
      ]) {
        requireQaFrameworkHealthy(tester);
        final selected = requireQaSuccess(
          await repository.switchWallet(peer.$1),
          'peer_select',
        );
        if (selected.activeWalletId != peer.$1) {
          throw const FullWalletQaFailure('qa_transfer_pair_selection_changed');
        }
        requireQaSuccess(
          await repository.sync(),
          'peer_existing_transfer_sync',
        );
        final identity = requireQaSuccess(
          await repository.networkStatus(),
          'peer_identity',
        );
        if (identity.nodePublicKey != peer.$2) {
          throw const FullWalletQaFailure('qa_transfer_pair_identity_changed');
        }
        final balance = requireQaSuccess(
          await repository.balance(WalletAssetKind.usdt),
          'peer_balance',
        );
        final feed = requireQaSuccess(
          await repository.activityFeed(WalletAssetKind.usdt),
          'peer_history',
        );
        final matches = feed.activities
            .where((item) => item.txid == txid)
            .toList();
        if (matches.length > 1 ||
            matches.any(
              (item) =>
                  item.direction != peer.$4 ||
                  item.amount?.units != amountUnits,
            )) {
          throw const FullWalletQaFailure('qa_transfer_pair_history_changed');
        }
        settled =
            settled &&
            balance.onchainSettled.units == peer.$3 &&
            balance.onchainSpendable.units == peer.$3 &&
            matches.length == 1 &&
            matches.single.status == WalletActivityStatus.succeeded;
      }
      return settled;
    });
  } finally {
    final restored = requireQaSuccess(
      await repository.switchWallet(activeId),
      'peer_restore_selection',
    );
    if (restored.activeWalletId != activeId) {
      throw const FullWalletQaFailure(
        'qa_transfer_pair_selection_not_restored',
      );
    }
  }
}

/// Native RGB outgoing transfers wait for peer ACK and Bitcoin confirmations.
/// Admit only those exact typed on-chain states for the already bound txid.
void requireQaOriginalTransferCheckpoint({
  required bool identityMatches,
  required List<WalletActivity> matches,
  required int amountUnits,
}) {
  final match = matches.length == 1 ? matches.single : null;
  final statusAdmitted = const {
    WalletActivityStatus.pending,
    WalletActivityStatus.waitingCounterparty,
    WalletActivityStatus.waitingSafeHeight,
    WalletActivityStatus.waitingBroadcast,
    WalletActivityStatus.waitingConfirmations,
    WalletActivityStatus.succeeded,
  }.contains(match?.status);
  final sourceMatches =
      match?.source == WalletActivitySource.rgbTransfer &&
      match?.operation == WalletActivityOperation.rgbSend &&
      match?.rail == PaymentRail.onchain;
  if (!identityMatches ||
      matches.length != 1 ||
      !sourceMatches ||
      match?.direction != WalletActivityDirection.sent ||
      match?.amount?.units != amountUnits ||
      !statusAdmitted) {
    throw FullWalletQaFailure(
      'qa_transfer_original_native_checkpoint_changed',
      [
        {
          'identity_matches': identityMatches,
          'match_count': matches.length,
          'source_matches': sourceMatches,
          'source': match?.source.name,
          'operation': match?.operation.name,
          'direction': match?.direction.name,
          'status': match?.status.name,
          'status_admitted': statusAdmitted,
          'units': match?.amount?.units,
          'amount_matches': match?.amount?.units == amountUnits,
        },
      ],
    );
  }
}

Future<Map<String, Object?>> _snapshot(WalletRepository repository) async {
  final portfolio = requireQaSuccess(await repository.portfolio(), 'portfolio');
  final network = requireQaSuccess(await repository.networkStatus(), 'network');
  return {
    'node_public_key': network.nodePublicKey,
    'block_height': network.blockHeight,
    'btc_settled_sats': portfolio.bitcoin.onchainSettled.units,
    'btc_spendable_sats': portfolio.bitcoin.onchainSpendable.units,
    'bfa_settled_units': portfolio.usdt?.onchainSettled.units,
    'bfa_spendable_units': portfolio.usdt?.onchainSpendable.units,
    'bfa_future_units': portfolio.usdt?.onchainFuture.units,
  };
}

/// Dismiss the phrase-entry keyboard before targeting the real Continue button.
/// Phrase pasting deliberately focuses the last field; checksum readiness alone
/// does not make a button covered by the platform keyboard hit-testable.
Future<void> qualifyImportContinueUi(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 300));
  await _untilUi(
    tester,
    () => tester.view.viewInsets.bottom == 0,
    failureCode: 'qa_import_keyboard_not_dismissed',
  );
  await _tap(
    tester,
    find.widgetWithText(CustomButton, 'Continue'),
    failureCode: 'qa_import_continue',
  );
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  String failureCode = 'qa_import_tap',
}) async {
  await _untilUi(
    tester,
    () => finder.evaluate().length == 1,
    failureCode: '${failureCode}_missing',
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 800));
  final visible = finder.hitTestable();
  await _untilUi(
    tester,
    () => visible.evaluate().length == 1,
    failureCode: '${failureCode}_blocked',
  );
  requireQaFrameworkHealthy(tester);
  await tester.tap(visible, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 800));
  requireQaFrameworkHealthy(tester);
}

Future<void> _untilUi(
  WidgetTester tester,
  bool Function() predicate, {
  String failureCode = 'qa_import_ui_timeout',
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (DateTime.now().isBefore(deadline)) {
    requireQaFrameworkHealthy(tester);
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw FullWalletQaFailure(failureCode);
}

Future<void> _untilWallet(
  WidgetTester tester,
  Future<bool> Function() predicate,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (DateTime.now().isBefore(deadline)) {
    requireQaFrameworkHealthy(tester);
    if (await predicate()) return;
    await tester.pump(const Duration(milliseconds: 500));
  }
  throw const FullWalletQaFailure('qa_import_wallet_state_timeout');
}

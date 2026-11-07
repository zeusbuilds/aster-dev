import 'dart:convert';
import 'dart:io' show pid;

import 'package:aster/core/core.dart';
import 'package:aster/features/onboarding/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:aster/main.dart';
import 'package:aster/shared/shared.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/full_wallet_home_observation.dart';
import 'support/full_wallet_import_transfer.dart';
import 'support/full_wallet_qa.dart';
import 'support/full_wallet_rgb_checkpoint.dart';
import 'support/full_wallet_rgb_l1.dart';
import 'support/full_wallet_rgb_setup.dart';
import 'support/full_wallet_send_ui.dart';
import 'support/full_wallet_test_guard.dart';

const _runId = String.fromEnvironment('ASTER_QA_RUN_ID');
const _controlUrl = String.fromEnvironment('ASTER_QA_CONTROL_URL');
const _storageRunId = String.fromEnvironment('ASTER_QA_STORAGE_RUN_ID');
const _resumePublicIdentity = String.fromEnvironment(
  'ASTER_QA_RESUME_PUBLIC_IDENTITY',
);
const _resumeBtcDestination = String.fromEnvironment(
  'ASTER_QA_RESUME_BTC_DESTINATION',
);
const _resumeCohort = String.fromEnvironment('ASTER_QA_RESUME_COHORT');
const _resumeBtcTxid = String.fromEnvironment('ASTER_QA_RESUME_BTC_TXID');
const _resumeRgbTxid = String.fromEnvironment('ASTER_QA_RESUME_RGB_TXID');
const _resumeReturnInvoice = String.fromEnvironment(
  'ASTER_QA_RESUME_RETURN_INVOICE',
);
const _resumeReturnInvoiceHash = String.fromEnvironment(
  'ASTER_QA_RESUME_RETURN_INVOICE_SHA256',
);
const _stage = String.fromEnvironment(
  'ASTER_QA_STAGE',
  defaultValue: 'lifecycle',
);
const _nativeTimeout = Duration(minutes: 5);

void main() => runFullWalletFlowQualification();

/// The separate RGB_L1 integration entrypoint uses only Debug isolated storage.
/// Normal Aster startup and all product/release admission gates are unchanged.
void runFullWalletFlowQualification({
  bool qualifyLocalRgbL1 = false,
  bool observeCompletedHome = false,
}) {
  final qualifiedServices = qualifyLocalRgbL1
      ? requireLocalRgbL1Services(
          WalletServiceConfiguration.fromEnvironment(),
          requireUsdt: {
            'rgb-l1-full',
            'rgb-l1-resume-funded',
            'rgb-l1-resume-return',
          }.contains(_stage),
        )
      : null;
  final binding = FullWalletQaIntegrationBinding();
  // Keep the real accessibility tree available throughout device inspection.
  // Establish the platform-owned semantics lifetime before the test baseline,
  // then restore it without disabling the framework's handle leak checks.
  binding.platformDispatcher.semanticsEnabledTestValue = true;
  tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);

  testWidgets('real isolated wallet lifecycle and local funded flows', (
    tester,
  ) async {
    final historicalReadOnly = {
      'restore',
      'reconcile-mint',
      'reconcile-transfer',
    }.contains(_stage);
    final completedCheckpoint = qualifyLocalRgbL1
        ? await readQaFundedCheckpoint(
            _storageRunId.isEmpty ? _runId : _storageRunId,
          )
        : null;
    if (observeCompletedHome &&
        (!qualifyLocalRgbL1 || completedCheckpoint == null)) {
      throw const FullWalletQaFailure('qa_home_completed_store_required');
    }
    final readOnly = historicalReadOnly || completedCheckpoint != null;
    final resumeFunded = _stage == 'rgb-l1-resume-funded';
    final resumeReturn = _stage == 'rgb-l1-resume-return';
    final control = FullWalletQaControl(
      runId: _runId,
      controlUrl: _controlUrl,
      readOnly: readOnly,
      initialSequence: completedCheckpoint == null ? 0 : 1000,
      beforeFinancialDispatch: () => requireQaFrameworkHealthy(tester),
    );
    ProviderContainer? container;
    WalletRepository? cleanupRepository;
    FullWalletQaStorage? retainedStorage;
    var completed = false;
    var secretScreen = false;
    try {
      if (!{
        'lifecycle',
        'full',
        'rgb-l1-full',
        'rgb-l1-resume-funded',
        'rgb-l1-resume-return',
        'restore',
        'reconcile-mint',
        'reconcile-transfer',
      }.contains(_stage)) {
        throw const FullWalletQaFailure('qa_stage_invalid');
      }
      if (qualifyLocalRgbL1) {
        if (!{
          'lifecycle',
          'rgb-l1-full',
          'rgb-l1-resume-funded',
          'rgb-l1-resume-return',
        }.contains(_stage)) {
          throw const FullWalletQaFailure('qa_local_l1_stage_invalid');
        }
      } else {
        if (_stage == 'rgb-l1-full' || resumeFunded || resumeReturn) {
          throw const FullWalletQaFailure('qa_local_l1_entrypoint_required');
        }
        requireQaSupportedFundingStage(_stage);
      }
      final storage = await FullWalletQaStorage.open(
        runId: _storageRunId.isEmpty ? _runId : _storageRunId,
        existing: readOnly || resumeFunded || resumeReturn,
        restoreMissing: !historicalReadOnly
            ? null
            : (root) async {
                final receipt = await control.request(
                  'fixture_restore_requested',
                  {'storage_root': root.path, 'storage_run_id': _storageRunId},
                );
                if (receipt['restore_verified'] != true) {
                  throw const FullWalletQaFailure('qa_restore_not_verified');
                }
              },
      );
      retainedStorage = storage;
      await control.event('test_started', {
        'stage': _stage,
        'process_id': pid,
        'read_only_checkpoint': completedCheckpoint != null,
      });
      container = await storage.bootstrap(
        qualifiedLocalL1Services: qualifiedServices,
        readOnlyCheckpoint: completedCheckpoint,
        onReadOnlyAudit: (evidence) =>
            control.event('readonly_native_audit_passed', evidence),
        onFailureLogs: (evidence) =>
            control.event('native_failure_logs_copied', evidence),
      );
      var repository = await container.read(walletRepositoryProvider.future);
      cleanupRepository = repository;
      final services = container.read(walletServiceConfigurationProvider);
      if (services.environment != BlockchainEnvironment.regtest ||
          services.vssUrl != null ||
          services.lspBaseUrl != null) {
        throw const FullWalletQaFailure('qa_local_onchain_profile_required');
      }
      await control.preflight(services);
      if (qualifyLocalRgbL1) await recordQaNativeRuntime(control);
      if (completedCheckpoint != null) {
        final pending = requireQaSuccess(
          await repository.paymentSubmissionStatus(),
          'cold_process_no_pending',
        );
        if (pending?.requiresReconciliation == true) {
          throw const FullWalletQaFailure(
            'qa_cold_process_pending_native_or_app',
          );
        }
        final verified = await verifyQaFundedCheckpoint(
          storage: storage,
          repository: repository,
          expected: completedCheckpoint,
          snapshot: await _publicSnapshot(repository),
          assetId: services.usdtAsset!.contractId,
        );
        if (observeCompletedHome) {
          // Separate from strict cold observation: normal Home background
          // refresh is deliberately allowed; payment commands are never used.
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: FullWalletQaSecurityLifecycle(
                security: container.read(securityControllerProvider),
                child: const AsterApp(),
              ),
            ),
          );
          await qualifyCompletedHomeObservation(
            tester: tester,
            container: container,
            control: control,
            checkpoint: verified,
          );
          binding.reportData = {
            'stage': 'rgb-l1-home-observation',
            'checkpoint': verified,
            'ordinary_home_refresh_allowed': true,
            'new_payment_commands': false,
          };
          await control.event('test_passed', {
            'stage': 'rgb-l1-home-observation',
          });
          completed = true;
          return;
        }
        await control.event('funded_cold_process_reopen_passed', {
          ...verified,
          'process_id': pid,
          'generic_refresh_invoked': false,
          'app_ui_mounted': false,
          'no_new_payment_commands': true,
        });
        await control.event('test_passed', {
          'stage': 'rgb-l1-readonly-cold-reopen',
        });
        binding.reportData = {
          'stage': 'rgb-l1-readonly-cold-reopen',
          'checkpoint': verified,
        };
        completed = true;
        return;
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: FullWalletQaSecurityLifecycle(
            security: container.read(securityControllerProvider),
            child: const AsterApp(),
          ),
        ),
      );

      if (resumeReturn) {
        if (_storageRunId.isEmpty ||
            _storageRunId == _runId ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(_resumePublicIdentity) ||
            !RegExp(r'^[a-f0-9]{32}$').hasMatch(_resumeCohort) ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(_resumeBtcTxid) ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(_resumeRgbTxid) ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(_resumeReturnInvoiceHash) ||
            _resumeReturnInvoice.isEmpty ||
            sha256.convert(utf8.encode(_resumeReturnInvoice)).toString() !=
                _resumeReturnInvoiceHash) {
          throw const FullWalletQaFailure('qa_resume_return_scope_invalid');
        }
        final registry = requireQaSuccess(
          await repository.load(),
          'resume_return_load',
        );
        final active = registry.activeProfile;
        if (active == null ||
            registry.profiles.length != 1 ||
            registry.readyProfiles.length != 1 ||
            await readQaNativeCohort(storage, active.id) != _resumeCohort) {
          throw const FullWalletQaFailure('qa_resume_return_cohort_changed');
        }
        requireQaSuccess(await repository.sync(), 'resume_return_sync');
        final snapshot = await _publicSnapshot(repository);
        final pending = requireQaSuccess(
          await repository.paymentSubmissionStatus(),
          'resume_return_pending',
        );
        final btcFeed = requireQaSuccess(
          await repository.activityFeed(WalletAssetKind.bitcoin),
          'resume_return_btc_history',
        );
        final rgbFeed = requireQaSuccess(
          await repository.activityFeed(WalletAssetKind.usdt),
          'resume_return_rgb_history',
        );
        final btcSent = btcFeed.activities
            .where((row) => row.direction == WalletActivityDirection.sent)
            .toList();
        final receivedRgb = rgbFeed.activities
            .where(
              (row) =>
                  row.direction == WalletActivityDirection.received &&
                  row.txid == _resumeRgbTxid &&
                  row.amount?.units == 100 &&
                  row.status == WalletActivityStatus.succeeded,
            )
            .toList();
        if (snapshot['public_identity'] != _resumePublicIdentity ||
            snapshot['bfa_settled_units'] != 100 ||
            snapshot['bfa_spendable_units'] != 100 ||
            pending?.requiresReconciliation == true ||
            btcSent.length != 1 ||
            btcSent.single.txid != _resumeBtcTxid ||
            btcSent.single.amount?.units != 1000 ||
            btcSent.single.status != WalletActivityStatus.succeeded ||
            receivedRgb.length != 1 ||
            rgbFeed.activities.any(
              (row) => row.direction == WalletActivityDirection.sent,
            )) {
          throw const FullWalletQaFailure(
            'qa_resume_return_checkpoint_changed',
          );
        }
        await control.event('retained_return_checkpoint_verified', {
          'storage_run_id': storage.runId,
          'recovery_cohort': _resumeCohort,
          'confirmed_btc_txid': _resumeBtcTxid,
          'confirmed_rgb_receive_txid': _resumeRgbTxid,
          ...snapshot,
        });
        await qualifyLocalRgbL1ReturnFlow(
          tester: tester,
          container: container,
          repository: repository,
          control: control,
          invoice: _resumeReturnInvoice,
          confirmedBtcTxid: _resumeBtcTxid,
          receivedRgbTxid: _resumeRgbTxid,
        );
        final snapshotAfter = await _publicSnapshot(repository);
        final checkpoint = await saveQaFundedCheckpoint(
          storage: storage,
          repository: repository,
          snapshot: snapshotAfter,
          assetId: services.usdtAsset!.contractId,
        );
        await control.event('funded_checkpoint_saved', checkpoint);
        await control.event('test_passed', {'stage': _stage, ...snapshotAfter});
        binding.reportData = {
          'stage': _stage,
          'wallet': snapshotAfter,
          'checkpoint': checkpoint,
        };
        completed = true;
        return;
      }

      if (resumeFunded) {
        if (_storageRunId.isEmpty ||
            _storageRunId == _runId ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(_resumePublicIdentity) ||
            _resumeBtcDestination.isEmpty) {
          throw const FullWalletQaFailure('qa_resume_scope_invalid');
        }
        final registry = requireQaSuccess(
          await repository.load(),
          'resume_funded_load',
        );
        if (registry.profiles.length != 1 ||
            registry.readyProfiles.length != 1 ||
            registry.activeProfile == null) {
          throw const FullWalletQaFailure('qa_resume_registry_changed');
        }
        requireQaSuccess(await repository.sync(), 'resume_funded_sync');
        final snapshot = await _publicSnapshot(repository);
        if (snapshot['public_identity'] != _resumePublicIdentity ||
            snapshot['btc_settled_sats'] != 100000 ||
            snapshot['btc_spendable_sats'] != 100000 ||
            snapshot['bfa_settled_units'] != 0 ||
            snapshot['bfa_spendable_units'] != 0 ||
            requireQaSuccess(
                  await repository.paymentSubmissionStatus(),
                  'resume_funded_submission',
                ) !=
                null) {
          throw const FullWalletQaFailure('qa_resume_pre_send_state_changed');
        }
        for (final asset in [WalletAssetKind.bitcoin, WalletAssetKind.usdt]) {
          final feed = requireQaSuccess(
            await repository.activityFeed(asset),
            'resume_funded_activity',
          );
          if (feed.activities.any(
            (row) => row.direction == WalletActivityDirection.sent,
          )) {
            throw const FullWalletQaFailure('qa_resume_previous_send_present');
          }
        }
        await control.event('retained_funded_checkpoint_verified', {
          'storage_run_id': _storageRunId,
          ...snapshot,
        });
        await qualifyLocalRgbL1FundedFlows(
          tester: tester,
          container: container,
          repository: repository,
          control: control,
          retainedBtcDestination: _resumeBtcDestination,
        );
        final finalSnapshot = await _publicSnapshot(repository);
        final checkpoint = await saveQaFundedCheckpoint(
          storage: storage,
          repository: repository,
          snapshot: finalSnapshot,
          assetId: services.usdtAsset!.contractId,
        );
        await control.event('funded_checkpoint_saved', checkpoint);
        await control.event('test_passed', {'stage': _stage, ...finalSnapshot});
        binding.reportData = {'stage': _stage, 'wallet': finalSnapshot};
        completed = true;
        return;
      }

      if (_stage == 'reconcile-transfer') {
        final validation = await control.request(
          'fixture_transfer_validation_requested',
          {'storage_run_id': _storageRunId},
        );
        final expected = validation['expected_transfer'];
        if (expected is! Map<String, Object?> ||
            expected['amount_units'] != 1000000 ||
            expected['original_units'] != 4000000 ||
            expected['imported_units'] != 1000000 ||
            expected['profile_ids'] is! List<Object?> ||
            expected['txid'] is! String ||
            expected['invoice'] is! String ||
            expected['original_public_key'] is! String ||
            expected['imported_public_key'] is! String) {
          throw const FullWalletQaFailure('qa_transfer_checkpoint_invalid');
        }
        final registry = requireQaSuccess(
          await repository.load(),
          'transfer_reconcile_load',
        );
        final ids = registry.readyProfiles.map((profile) => profile.id).toList()
          ..sort();
        final activeId = registry.activeWalletId;
        if (registry.profiles.length != 2 ||
            ids.length != 2 ||
            activeId != expected['active_wallet_id'] ||
            !const DeepCollectionEquality().equals(
              ids,
              expected['profile_ids'],
            )) {
          throw const FullWalletQaFailure(
            'qa_transfer_checkpoint_profiles_changed',
          );
        }
        final byPublicKey = <String, String>{};
        try {
          for (final id in ids) {
            requireQaSuccess(
              await repository.switchWallet(id),
              'transfer_reconcile_identify',
            );
            final identity = requireQaSuccess(
              await repository.networkStatus(),
              'transfer_reconcile_identity',
            );
            byPublicKey[identity.publicIdentity] = id;
          }
        } finally {
          if (activeId != null) {
            requireQaSuccess(
              await repository.switchWallet(activeId),
              'transfer_reconcile_restore_selection',
            );
          }
        }
        final originalKey = expected['original_public_key']! as String;
        final importedKey = expected['imported_public_key']! as String;
        if (byPublicKey.length != 2 ||
            !byPublicKey.containsKey(originalKey) ||
            !byPublicKey.containsKey(importedKey)) {
          throw const FullWalletQaFailure(
            'qa_transfer_checkpoint_identity_changed',
          );
        }
        requireQaBlindPreview(
          requireQaSuccess(
            await repository.previewPayment(
              WalletPaymentTarget.usdtOnchain,
              expected['invoice']! as String,
            ),
            'transfer_reconcile_existing_invoice',
          ),
        );
        await qualifyExistingTransferPair(
          tester: tester,
          repository: repository,
          senderId: byPublicKey[originalKey]!,
          senderPublicKey: originalKey,
          receiverId: byPublicKey[importedKey]!,
          receiverPublicKey: importedKey,
          txid: expected['txid']! as String,
          amountUnits: 1000000,
          senderUnits: 4000000,
          receiverUnits: 1000000,
          requireExistingCheckpoint: true,
        );
        final pair = await _publicWalletPair(repository);
        final snapshot = await _publicSnapshot(repository);
        await control.event('retained_transfer_reconciliation_passed', {
          'txid': expected['txid'],
          'wallet_pair': pair,
          ...snapshot,
        });
        await control.event('test_passed', {
          'stage': _stage,
          'txid': expected['txid'],
          'wallet_pair': pair,
          ...snapshot,
        });
        binding.reportData = {'reconcile_transfer': pair};
        completed = true;
        return;
      }

      if (_stage == 'reconcile-mint') {
        final validation = await control.request(
          'fixture_reconcile_validation_requested',
          {'storage_run_id': _storageRunId},
        );
        final expected = validation['expected_snapshot'];
        if (expected is! Map<String, Object?> ||
            expected['bfa_settled_units'] != 5000000 ||
            expected['bfa_spendable_units'] != 5000000) {
          throw const FullWalletQaFailure('qa_reconcile_checkpoint_invalid');
        }
        final registry = requireQaSuccess(
          await repository.load(),
          'reconcile_load',
        );
        final network = requireQaSuccess(
          await repository.networkStatus(),
          'reconcile_identity',
        );
        if (registry.profiles.length != 1 ||
            registry.readyProfiles.length != 1 ||
            registry.activeProfile == null ||
            network.publicIdentity != expected['node_public_key']) {
          throw const FullWalletQaFailure(
            'qa_reconcile_original_wallet_changed',
          );
        }
        await _untilWallet(tester, () async {
          requireQaSuccess(
            await repository.sync(),
            'reconcile_existing_mint_sync',
          );
          final snapshot = await _publicSnapshot(repository);
          if (snapshot['node_public_key'] != expected['node_public_key']) {
            throw const FullWalletQaFailure(
              'qa_reconcile_original_wallet_changed',
            );
          }
          return [
            'btc_future_sats',
            'btc_spendable_sats',
            'bfa_settled_units',
            'bfa_spendable_units',
          ].every((key) => snapshot[key] == expected[key]);
        });
        final snapshot = await _publicSnapshot(repository);
        if (expected.keys.any((key) => snapshot[key] != expected[key])) {
          throw const FullWalletQaFailure('qa_reconcile_state_changed');
        }
        await control.event('retained_mint_reconciliation_passed', snapshot);
        await control.event('test_passed', {'stage': _stage, ...snapshot});
        binding.reportData = {'reconcile_mint': snapshot};
        completed = true;
        return;
      }

      if (_stage == 'restore') {
        final registry = requireQaSuccess(await repository.load(), 'restore');
        if (registry.readyProfiles.isEmpty || registry.activeProfile == null) {
          throw const FullWalletQaFailure('qa_restore_no_active_wallet');
        }
        final snapshot = await _publicSnapshot(repository);
        final validation = await control.request(
          'fixture_restore_validation_requested',
          {'storage_run_id': _storageRunId},
        );
        final expected = validation['expected_snapshot'];
        if (expected is! Map<String, Object?> ||
            [
              'node_public_key',
              'btc_settled_sats',
              'btc_spendable_sats',
              'bfa_settled_units',
              'bfa_spendable_units',
            ].any((key) => snapshot[key] != expected[key]) ||
            registry.readyProfiles.length != 2) {
          throw const FullWalletQaFailure('qa_restore_state_changed');
        }
        final pair = await _publicWalletPair(repository);
        if (!const DeepCollectionEquality().equals(
          pair,
          validation['expected_pair'],
        )) {
          throw const FullWalletQaFailure('qa_restore_wallet_pair_changed');
        }
        // Pair inspection restores the retained active selection. Read its
        // final snapshot again rather than publishing the earlier observation.
        final restoredSnapshot = await _publicSnapshot(repository);
        if ([
          'node_public_key',
          'btc_settled_sats',
          'btc_spendable_sats',
          'bfa_settled_units',
          'bfa_spendable_units',
        ].any((key) => restoredSnapshot[key] != expected[key])) {
          throw const FullWalletQaFailure('qa_restore_state_changed');
        }
        await control.event('retained_store_restore_passed', {
          ...restoredSnapshot,
          'wallet_pair': pair,
        });
        await control.event('test_passed', {
          'stage': _stage,
          ...restoredSnapshot,
          'wallet_pair': pair,
        });
        binding.reportData = {'restore': restoredSnapshot, 'wallet_pair': pair};
        completed = true;
        return;
      }

      final initial = requireQaSuccess(await repository.load(), 'initial_load');
      if (initial.profiles.isNotEmpty) {
        throw const FullWalletQaFailure('qa_initial_registry_not_empty');
      }
      await _untilUi(
        tester,
        () => find.text('Create Wallet').evaluate().isNotEmpty,
      );
      await control.event('secret_screen_active');
      secretScreen = true;
      final createButton = find.widgetWithText(CustomButton, 'Create Wallet');
      final initialSecurity = container.read(securityControllerProvider);
      await control.event('onboarding_create_readiness', {
        'security_initialized': initialSecurity.initialized,
        'security_can_access_wallet': initialSecurity.canAccessWallet,
        'security_authenticating': initialSecurity.isAuthenticating,
        'security_captured': initialSecurity.isCaptured,
        'device_security_status': initialSecurity.deviceStatus?.name,
        'binding_lifecycle': tester.binding.lifecycleState?.name,
      });
      for (var attempt = 1; attempt <= 3; attempt += 1) {
        await _untilUi(tester, () {
          if (createButton.evaluate().length != 1) return false;
          final element = createButton.evaluate().single;
          final button = element.widget as CustomButton;
          final security = container!.read(securityControllerProvider);
          return security.canAccessWallet &&
              !security.isAuthenticating &&
              !security.isCaptured &&
              button.enabled &&
              !button.loading &&
              (ModalRoute.of(element)?.isCurrent ?? true) &&
              TickerMode.valuesOf(element).enabled &&
              AsterNavigationScope.maybeOf(element)?.inFlight != true;
        });
        await _tap(tester, createButton);
        final security = container.read(securityControllerProvider);
        final exists = container.exists(createWalletViewModelProvider);
        await control.event('onboarding_create_action_observed', {
          'attempt': attempt,
          'security_initialized': security.initialized,
          'security_authenticating': security.isAuthenticating,
          'security_locked': security.isLocked,
          'security_obscured': security.isObscured,
          'security_captured': security.isCaptured,
          'security_generation': security.generation,
          'device_security_status': security.deviceStatus?.name,
          'phrase_provider_exists': exists,
          'create_button_present': createButton.evaluate().length == 1,
        });
        if (exists ||
            security.isAuthenticating ||
            createButton.evaluate().length != 1 ||
            tester.widget<CustomButton>(createButton).loading) {
          break;
        }
        // This is the nonfinancial entry action only. A transition can have
        // exposed a button before its interaction owner settled. Retry solely
        // while no phrase provider exists and the same idle button remains;
        // never repeat provisioning or a payment action.
        await tester.pump(const Duration(milliseconds: 500));
      }
      await _untilUi(tester, () {
        // A read would create this auto-dispose provider if the tap was ignored.
        // Only observe the provider after the real protected journey owns it.
        if (!container!.exists(createWalletViewModelProvider)) return false;
        final state = container.read(createWalletViewModelProvider);
        if (state.error case final AppFailureException error) {
          throw qaAppFailure('onboarding_phrase', error.failure);
        }
        return state.value != null;
      });
      await control.event('onboarding_create_opened');
      // Only the quiz answers are held in memory. No recovery phrase is copied,
      // logged, serialized to a receipt, or included in screenshot evidence.
      final questions = container
          .read(createWalletViewModelProvider)
          .value!
          .questions;
      await _tap(tester, find.widgetWithText(CustomButton, 'Continue'));
      await control.event('onboarding_quiz_opened');
      for (final question in questions) {
        final choice = find.byKey(
          ValueKey(
            'quiz-option-${question.wordNumber}-${question.expectedWord}',
          ),
        );
        var confirmed = false;
        for (var attempt = 0; attempt < 4; attempt += 1) {
          await _tap(tester, choice);
          confirmed =
              container
                  .read(createWalletViewModelProvider)
                  .value
                  ?.isQuestionConfirmed(question) ==
              true;
          if (confirmed) break;
          // Only this nonfinancial input may be repeated. Provisioning and
          // payment mutation calls are never retried by the harness.
          await tester.pump(const Duration(milliseconds: 500));
        }
        if (!confirmed) {
          await control.event('quiz_input_failed', {
            'word_number': question.wordNumber,
          });
          throw const FullWalletQaFailure('qa_quiz_option_not_selected');
        }
        await control.event('onboarding_quiz_answered', {
          'word_number': question.wordNumber,
        });
      }
      if (container.read(createWalletViewModelProvider).value?.quizComplete !=
          true) {
        throw const FullWalletQaFailure('qa_quiz_not_confirmed');
      }
      await _tap(tester, find.widgetWithText(CustomButton, 'Continue'));
      final nameField = find.byKey(const ValueKey('wallet-name-field'));
      await _untilUi(tester, () => nameField.evaluate().isNotEmpty);
      await control.event('onboarding_name_opened');
      await tester.enterText(nameField, 'QA ${control.role}');
      await _untilUi(
        tester,
        () =>
            container!.read(createWalletViewModelProvider).value?.canSubmit ==
            true,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      await control.event('onboarding_create_submit_requested');
      await _tap(tester, find.widgetWithText(CustomButton, 'Create Wallet'));
      await _untilUi(tester, () {
        final value = container!.read(createWalletViewModelProvider).value;
        if (value?.failure case final failure?) {
          throw qaAppFailure('onboarding', failure);
        }
        return container.read(walletViewModelProvider).value?.activeWallet !=
            null;
      });
      await tester.pump(const Duration(milliseconds: 500));
      await control.event('secret_screen_cleared');
      secretScreen = false;
      final registry = requireQaSuccess(
        await repository.load(),
        'created_load',
      );
      final active = registry.activeProfile;
      if (active == null || registry.readyProfiles.length != 1) {
        throw const FullWalletQaFailure('qa_creation_not_committed');
      }
      final identity = requireQaSuccess(
        await repository.networkStatus(),
        'identity',
      );
      final zero = await _publicSnapshot(repository);
      if (zero['btc_settled_sats'] != 0 || zero['btc_spendable_sats'] != 0) {
        throw const FullWalletQaFailure('qa_created_wallet_not_zero');
      }
      await control.event('onboarding_passed', zero);

      for (var cycle = 1; cycle <= 3; cycle += 1) {
        await control.event('lifecycle_cycle_started', {'cycle': cycle});
        requireQaSuccess(await repository.suspend(), 'suspend_$cycle');
        final runtime = await container.read(walletRuntimeProvider.future);
        if (runtime.snapshot.phase != WalletRuntimePhase.suspended) {
          throw const FullWalletQaFailure('qa_suspend_phase_invalid');
        }
        final whileSuspended = await repository.networkStatus();
        if (whileSuspended is! AppFailureResult<WalletNetworkStatus>) {
          throw const FullWalletQaFailure('qa_suspended_read_admitted');
        }
        requireQaSuccess(await repository.resume(), 'resume_$cycle');
        final reopened = requireQaSuccess(
          await repository.networkStatus(),
          'reopen_identity',
        );
        if (reopened.publicIdentity != identity.publicIdentity) {
          throw const FullWalletQaFailure('qa_reopen_identity_changed');
        }
        await control.event('lifecycle_cycle_passed', {'cycle': cycle});
      }

      // Tear down every production provider, then bootstrap another production
      // container against the same retained directories and secure namespace.
      requireQaSuccess(await repository.dispose(), 'dispose_before_bootstrap');
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      container = null;
      cleanupRepository = null;
      container = await storage.bootstrap(
        qualifiedLocalL1Services: qualifiedServices,
        onFailureLogs: (evidence) =>
            control.event('native_failure_logs_copied', evidence),
      );
      repository = await container.read(walletRepositoryProvider.future);
      cleanupRepository = repository;
      final persisted = requireQaSuccess(
        await repository.load(),
        'persisted_load',
      );
      final persistedIdentity = requireQaSuccess(
        await repository.networkStatus(),
        'persisted_identity',
      );
      if (persisted.activeWalletId != active.id ||
          persistedIdentity.publicIdentity != identity.publicIdentity) {
        throw const FullWalletQaFailure('qa_persisted_identity_changed');
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: FullWalletQaSecurityLifecycle(
            security: container.read(securityControllerProvider),
            child: const AsterApp(),
          ),
        ),
      );
      await control.event(
        'same_store_bootstrap_passed',
        await _publicSnapshot(repository),
      );
      Map<String, Object?>? pairCheckpoint;
      if (_stage == 'rgb-l1-full') {
        await qualifyLocalRgbL1FundedFlows(
          tester: tester,
          container: container,
          repository: repository,
          control: control,
        );
      }
      if (_stage == 'full') {
        await _fundedFlows(tester, container, repository, control);
        await qualifyImportedWalletTransfer(
          tester: tester,
          container: container,
          repository: repository,
          control: control,
          sensitiveScreenChanged: (active) => secretScreen = active,
        );
        pairCheckpoint = await _publicWalletPair(repository);
      }
      final finalSnapshot = await _publicSnapshot(repository);
      if (_stage == 'rgb-l1-full') {
        final checkpoint = await saveQaFundedCheckpoint(
          storage: storage,
          repository: repository,
          snapshot: finalSnapshot,
          assetId: services.usdtAsset!.contractId,
        );
        await control.event('funded_checkpoint_saved', checkpoint);
      }
      await control.event('test_passed', {
        'stage': _stage,
        ...finalSnapshot,
        if (_stage == 'full') 'wallet_pair': pairCheckpoint,
      });
      binding.reportData = {
        'stage': _stage,
        'wallet': finalSnapshot,
        if (_stage == 'full') 'wallet_pair': pairCheckpoint,
      };
      completed = true;
    } catch (error, stack) {
      final failure = error is FullWalletQaFailure
          ? error
          : FullWalletQaFailure('qa_unexpected_${error.runtimeType}');
      try {
        await control.event('test_failed', {
          'code': failure.code,
          'diagnostics': failure.diagnostics,
          'sensitive_screen_active': secretScreen,
        });
      } catch (_) {
        // An unavailable diagnostics relay must not replace the original
        // failure or encourage replaying a possibly committed wallet action.
      }
      Error.throwWithStackTrace(failure, stack);
    } finally {
      if (cleanupRepository != null) {
        final cleanup = await cleanupRepository.dispose();
        try {
          await control.event('test_cleanup', {
            'native_disposed': cleanup is AppSuccess<void>,
          });
        } catch (_) {
          // Awaited native cleanup remains authoritative if reporting fails.
        }
        if (cleanup is AppSuccess<void> && retainedStorage != null) {
          try {
            final backup = await control.request('fixture_backup_requested', {
              'storage_root': retainedStorage.root.path,
              'native_disposed': true,
              'stage': _stage,
            });
            if (backup['backup_verified'] != true) {
              throw const FullWalletQaFailure('qa_fixture_backup_not_verified');
            }
            await control.event('fixture_backup_verified');
          } catch (_) {
            if (completed) rethrow;
            // Preserve the original failure. Runner evidence records the
            // missing backup acknowledgement and must not reinstall this run.
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      container?.dispose();
      control.close();
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}

Future<void> _fundedFlows(
  WidgetTester tester,
  ProviderContainer container,
  WalletRepository repository,
  FullWalletQaControl control,
) async {
  final request = requireQaSuccess(
    await repository.createReceiveRequest(WalletPaymentTarget.bitcoinOnchain),
    'btc_receive',
  );
  final funding = await control.request('fund_requested', {
    'address': request.displayValue,
    'amount_sats': 2000000,
  });
  await _untilWallet(tester, () async {
    requireQaSuccess(await repository.sync(), 'btc_funding_sync');
    final value = requireQaSuccess(
      await repository.balance(WalletAssetKind.bitcoin),
      'btc_funding_balance',
    );
    return value.onchainSettled.units == 2000000 &&
        value.onchainSpendable.units == 2000000;
  });
  await control.event('btc_receive_passed', await _publicSnapshot(repository));
  final address = funding['btc_send_address'];
  if (address is! String) {
    throw const FullWalletQaFailure('qa_btc_destination_missing');
  }
  requireQaSuccess(
    await repository.previewPayment(
      WalletPaymentTarget.bitcoinOnchain,
      address,
    ),
    'btc_preview',
  );
  final sent = await qualifySendUi(
    tester: tester,
    container: container,
    repository: repository,
    control: control,
    target: WalletPaymentTarget.bitcoinOnchain,
    destination: address,
    amountUnits: 20000,
  );
  await control.request('btc_confirm_requested', {
    'txid': sent.referenceId,
    'recipient': address,
    'amount_sats': 20000,
  });
  await _untilWallet(tester, () async {
    requireQaSuccess(await repository.sync(), 'btc_send_sync');
    final feed = requireQaSuccess(
      await repository.activityFeed(WalletAssetKind.bitcoin),
      'btc_send_history',
    );
    final matches = feed.activities
        .where(
          (item) =>
              item.txid == sent.referenceId &&
              item.direction == WalletActivityDirection.sent,
        )
        .toList();
    return matches.length == 1 &&
        matches.single.status == WalletActivityStatus.succeeded;
  });
  await control.event('btc_send_passed', {
    'txid': sent.referenceId,
    ...await _publicSnapshot(repository),
  });
  final rgbReceive = await qualifyRgbReceiveUi(
    tester: tester,
    container: container,
    repository: repository,
    control: control,
  );
  await control.request('bfa_mint_requested', {
    'invoice': rgbReceive.encodedRequest,
    'amount_units': 5000000,
  });
  await _untilWallet(tester, () async {
    requireQaSuccess(await repository.sync(), 'bfa_receive_sync');
    final balance = requireQaSuccess(
      await repository.balance(WalletAssetKind.usdt),
      'bfa_receive_balance',
    );
    return balance.onchainSettled.units == 5000000 &&
        balance.onchainSpendable.units == 5000000;
  });
  await control.event('bfa_receive_passed', await _publicSnapshot(repository));
}

Future<Map<String, Object?>> _publicSnapshot(
  WalletRepository repository,
) async {
  final portfolio = requireQaSuccess(await repository.portfolio(), 'portfolio');
  final network = requireQaSuccess(await repository.networkStatus(), 'network');
  return {
    'public_identity': network.publicIdentity,
    'identity_kind': network.nodePublicKey == null
        ? 'native-wallet'
        : 'lightning-node',
    if (network.nodePublicKey != null) 'node_public_key': network.nodePublicKey,
    'block_height': network.blockHeight,
    'btc_settled_sats': portfolio.bitcoin.onchainSettled.units,
    'btc_spendable_sats': portfolio.bitcoin.onchainSpendable.units,
    'btc_future_sats': portfolio.bitcoin.onchainFuture.units,
    'bfa_settled_units': portfolio.usdt?.onchainSettled.units,
    'bfa_spendable_units': portfolio.usdt?.onchainSpendable.units,
    'bfa_future_units': portfolio.usdt?.onchainFuture.units,
  };
}

/// Read both retained profiles and restore the original active selection.
/// Selecting and syncing existing stores never creates an invoice or payment.
Future<Map<String, Object?>> _publicWalletPair(
  WalletRepository repository,
) async {
  final registry = requireQaSuccess(await repository.load(), 'pair_registry');
  final activeId = registry.activeWalletId;
  final ids = registry.readyProfiles.map((profile) => profile.id).toList()
    ..sort();
  if (registry.profiles.length != 2 ||
      ids.length != 2 ||
      ids.toSet().length != 2 ||
      activeId == null ||
      !ids.contains(activeId)) {
    throw const FullWalletQaFailure('qa_wallet_pair_registry_invalid');
  }
  final profiles = <Map<String, Object?>>[];
  try {
    for (final id in ids) {
      final selected = requireQaSuccess(
        await repository.switchWallet(id),
        'pair_select',
      );
      if (selected.activeWalletId != id) {
        throw const FullWalletQaFailure('qa_wallet_pair_selection_changed');
      }
      requireQaSuccess(await repository.sync(), 'pair_existing_store_sync');
      final snapshot = await _publicSnapshot(repository);
      profiles.add({
        'wallet_id': id,
        for (final key in [
          'node_public_key',
          'btc_settled_sats',
          'btc_future_sats',
          'btc_spendable_sats',
          'bfa_settled_units',
          'bfa_future_units',
          'bfa_spendable_units',
        ])
          key: snapshot[key],
      });
    }
  } finally {
    final restored = requireQaSuccess(
      await repository.switchWallet(activeId),
      'pair_restore_selection',
    );
    if (restored.activeWalletId != activeId ||
        restored.profiles.length != 2 ||
        restored.readyProfiles.length != 2 ||
        restored.readyProfiles
            .map((profile) => profile.id)
            .toSet()
            .difference(ids.toSet())
            .isNotEmpty) {
      throw const FullWalletQaFailure('qa_wallet_pair_selection_not_restored');
    }
  }
  if (profiles.map((profile) => profile['node_public_key']).toSet().length !=
      2) {
    throw const FullWalletQaFailure('qa_wallet_pair_identity_not_independent');
  }
  return {'active_wallet_id': activeId, 'profiles': profiles};
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _untilUi(tester, () => finder.evaluate().length == 1);
  await _untilUi(tester, () {
    final widget = tester.widget(finder);
    return widget is! CustomButton || (widget.enabled && !widget.loading);
  });
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 800));
  final visible = finder.hitTestable();
  await _untilUi(tester, () => visible.evaluate().length == 1);
  // Secret-bearing quiz keys must never be printed in hit-test diagnostics.
  requireQaFrameworkHealthy(tester);
  await tester.tap(visible, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 800));
}

Future<void> _untilUi(WidgetTester tester, bool Function() predicate) async {
  final deadline = DateTime.now().add(_nativeTimeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw const FullWalletQaFailure('qa_ui_state_timeout');
}

Future<void> _untilWallet(
  WidgetTester tester,
  Future<bool> Function() predicate,
) async {
  final deadline = DateTime.now().add(_nativeTimeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) return;
    await tester.pump(const Duration(milliseconds: 500));
  }
  throw const FullWalletQaFailure('qa_wallet_state_timeout');
}

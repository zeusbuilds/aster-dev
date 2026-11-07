import 'dart:convert';
import 'dart:io';

import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart' as sdk;

import 'full_wallet_qa.dart';

const _fileName = '.qa-funded-complete.json';
const _security = PlatformWalletStorageSecurity();

Future<Map<String, Object?>> _readPublicFile(
  File file, {
  bool appOwnedMetadata = true,
}) async {
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.length() > 64 * 1024) {
    throw const FullWalletQaFailure('qa_public_checkpoint_invalid');
  }
  if (appOwnedMetadata) await _security.verifyFile(file.path);
  final value = jsonDecode(await file.readAsString());
  if (value is! Map<String, Object?>) {
    throw const FullWalletQaFailure('qa_public_checkpoint_invalid');
  }
  return value;
}

/// Reads only non-secret metadata; it never restores, creates or authorizes.
/// A present malformed marker fails closed. An existing store without a marker
/// is still rejected by the normal fresh-run guard or explicit continuation.
Future<Map<String, Object?>?> readQaFundedCheckpoint(String runId) async {
  if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{2,63}$').hasMatch(runId)) {
    throw const FullWalletQaFailure('qa_checkpoint_scope_invalid');
  }
  final support = await getApplicationSupportDirectory();
  final file = File('${support.path}/aster_full_wallet_qa/$runId/$_fileName');
  if (await FileSystemEntity.type(file.path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    return null;
  }
  final value = await _readPublicFile(file);
  return validateQaFundedCheckpoint(value, runId);
}

Map<String, Object?> validateQaFundedCheckpoint(
  Map<String, Object?> value,
  String runId,
) {
  const keys = {
    'version',
    'complete',
    'storage_run_id',
    'wallet_id',
    'asset_id',
    'recovery_cohort',
    'snapshot',
    'sent',
    'pending_fence',
  };
  final snapshot = value['snapshot'];
  final sent = value['sent'];
  if (value['version'] != 1 ||
      value.keys.length != keys.length ||
      !keys.containsAll(value.keys) ||
      value['storage_run_id'] != runId ||
      value['complete'] != true ||
      value['pending_fence'] != false ||
      value['asset_id'] is! String ||
      !(value['asset_id'] as String).startsWith('rgb:') ||
      !RegExp(r'^[a-f0-9]{32}$')
          .hasMatch(value['wallet_id']?.toString() ?? '') ||
      snapshot is! Map<String, Object?> ||
      sent is! List<Object?> ||
      !RegExp(r'^[a-f0-9]{32}$')
          .hasMatch(value['recovery_cohort']?.toString() ?? '')) {
    throw const FullWalletQaFailure('qa_public_checkpoint_invalid');
  }
  if (!RegExp(r'^[a-f0-9]{64}$')
          .hasMatch(snapshot['public_identity']?.toString() ?? '') ||
      snapshot['identity_kind'] != 'native-wallet' ||
      snapshot['bfa_settled_units'] != 50 ||
      snapshot['bfa_spendable_units'] != 50 ||
      snapshot['bfa_future_units'] != 50 ||
      [
        'btc_settled_sats',
        'btc_spendable_sats',
        'btc_future_sats',
      ].any((key) => snapshot[key] is! int || (snapshot[key] as int) < 0) ||
      sent.length != 2) {
    throw const FullWalletQaFailure('qa_public_checkpoint_invalid');
  }
  for (var index = 0; index < 2; index += 1) {
    final row = sent[index];
    if (row is! Map<String, Object?> ||
        row.length != 4 ||
        row['asset'] != (index == 0 ? 'bitcoin' : 'usdt') ||
        row['gross_units'] != (index == 0 ? 1000 : 50) ||
        row['status'] != 'succeeded' ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['txid']?.toString() ?? '')) {
      throw const FullWalletQaFailure('qa_public_checkpoint_invalid');
    }
  }
  return value;
}

/// Observes the public cohort only AFTER the production existing-only open has
/// authenticated the SDK profile/native state. This is an acceptance check,
/// never a substitute for SDK authentication or restore freshness authority.
Future<String> readQaNativeCohort(
  FullWalletQaStorage storage,
  String walletId,
) async {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(walletId)) {
    throw const FullWalletQaFailure('qa_cohort_wallet_invalid');
  }
  return readQaNativeCohortFile(
    File('${storage.root.path}/native/$walletId/rgb-l1/rgb-sdk-profile.json'),
  );
}

Future<String> readQaNativeCohortFile(File file) async {
  final row = await _readPublicFile(
    file,
    // The SDK owns this authenticated file and excludes its parent from
    // backup. App metadata's per-file attribute policy does not apply here.
    appOwnedMetadata: false,
  );
  final cohort = row['recoveryCohort'];
  if (cohort is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(cohort)) {
    throw const FullWalletQaFailure('qa_native_cohort_invalid');
  }
  return cohort;
}

Future<void> recordQaNativeRuntime(FullWalletQaControl control) async {
  final info = await sdk.RgbLibWallet.getRuntimeInfo();
  if (!info.contractRegistration ||
      !info.durableOnchainRecovery ||
      !info.supportsDispatchedRgbRevocation ||
      !info.supportsExistingOnlyOpen) {
    throw const FullWalletQaFailure('qa_native_capability_missing');
  }
  await control.event('native_runtime_admitted', {
    'version': info.version,
    'source_revision': info.sourceRevision,
    'bridge_version': info.bridgeVersion,
    'integration_tree': info.integrationTree,
    'overlay_sha256': info.overlayPatchSha256,
    'source_lock_sha256': info.sourceLockSha256,
    'source_manifest_sha256': info.sourceManifestSha256,
    'contract_registration': info.contractRegistration,
    'durable_recovery': info.durableOnchainRecovery,
    'dispatched_rgb_revocation': info.supportsDispatchedRgbRevocation,
    'existing_only_open': info.supportsExistingOnlyOpen,
  });
}

Future<List<Map<String, Object?>>> _sent(WalletRepository repository) async {
  final rows = <Map<String, Object?>>[];
  for (final kind in [WalletAssetKind.bitcoin, WalletAssetKind.usdt]) {
    final feed = requireQaSuccess(
      await repository.activityFeed(kind),
      'checkpoint_activity',
    );
    final sent = feed.activities
        .where((row) => row.direction == WalletActivityDirection.sent)
        .toList();
    if (sent.length != 1 ||
        sent.single.status != WalletActivityStatus.succeeded ||
        sent.single.amount?.units !=
            (kind == WalletAssetKind.bitcoin ? 1000 : 50)) {
      throw const FullWalletQaFailure('qa_checkpoint_sent_history_mismatch');
    }
    rows.add({
      'asset': kind.name,
      'txid': sent.single.txid,
      'gross_units': sent.single.amount!.units,
      'status': sent.single.status.name,
    });
  }
  return rows;
}

Future<Map<String, Object?>> _current(
  FullWalletQaStorage storage,
  WalletRepository repository,
  Map<String, Object?> snapshot,
  String assetId,
) async {
  final registry = requireQaSuccess(await repository.load(), 'checkpoint_load');
  final active = registry.activeProfile;
  final submission = requireQaSuccess(
    await repository.paymentSubmissionStatus(),
    'checkpoint_no_pending',
  );
  if (active == null ||
      registry.profiles.length != 1 ||
      registry.readyProfiles.length != 1 ||
      submission?.requiresReconciliation == true ||
      snapshot['bfa_settled_units'] != 50 ||
      snapshot['bfa_spendable_units'] != 50 ||
      snapshot['bfa_future_units'] != 50) {
    throw const FullWalletQaFailure('qa_funded_checkpoint_mismatch');
  }
  return {
    'version': 1,
    'complete': true,
    'storage_run_id': storage.runId,
    'wallet_id': active.id,
    'asset_id': assetId,
    'recovery_cohort': await readQaNativeCohort(storage, active.id),
    'snapshot': {
      for (final entry in snapshot.entries)
        if (entry.key != 'block_height') entry.key: entry.value,
    },
    'sent': await _sent(repository),
    'pending_fence': false,
  };
}

Future<Map<String, Object?>> saveQaFundedCheckpoint({
  required FullWalletQaStorage storage,
  required WalletRepository repository,
  required Map<String, Object?> snapshot,
  required String assetId,
}) async {
  final file = File('${storage.root.path}/$_fileName');
  if (await file.exists()) {
    throw const FullWalletQaFailure('qa_checkpoint_already_completed');
  }
  final value = await _current(storage, repository, snapshot, assetId);
  validateQaFundedCheckpoint(value, storage.runId);
  await _security.replaceTextFile(file.path, jsonEncode(value));
  return value;
}

Future<Map<String, Object?>> verifyQaFundedCheckpoint({
  required FullWalletQaStorage storage,
  required WalletRepository repository,
  required Map<String, Object?> expected,
  required Map<String, Object?> snapshot,
  required String assetId,
}) async {
  final current = await _current(storage, repository, snapshot, assetId);
  // Fixed construction order gives an exact comparison of all public state.
  for (final key in current.keys) {
    if (jsonEncode(current[key]) != jsonEncode(expected[key])) {
      throw const FullWalletQaFailure('qa_cold_reopen_checkpoint_changed');
    }
  }
  return current;
}

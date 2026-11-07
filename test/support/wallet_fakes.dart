import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart'
    show RlnOperationTimeoutException;

final class MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};
  Object? readError;
  Object? writeError;
  Object? deleteError;
  bool commitWriteBeforeError = false;
  bool commitDeleteBeforeError = false;
  final readErrors = <String, Object>{};

  @override
  Future<bool> containsKey({required String key}) async =>
      values.containsKey(key);

  @override
  Future<Set<String>> keys() async {
    if (readError case final Object error) throw error;
    return values.keys.toSet();
  }

  @override
  Future<void> delete({required String key}) async {
    if (deleteError case final Object error) {
      if (commitDeleteBeforeError) values.remove(key);
      throw error;
    }
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    if (readErrors[key] case final Object error) throw error;
    if (readError case final Object error) throw error;
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    if (writeError case final Object error) {
      if (commitWriteBeforeError) values[key] = value;
      throw error;
    }
    values[key] = value;
  }
}

final class MemoryWalletRegistryDocumentStore
    implements WalletRegistryDocumentStore {
  String? document;
  Object? readError;
  Object? writeError;
  var readCount = 0;
  var writeCount = 0;

  @override
  Future<String?> read() async {
    readCount += 1;
    if (readError case final Object error) throw error;
    return document;
  }

  @override
  Future<void> write(String document) async {
    writeCount += 1;
    if (writeError case final Object error) throw error;
    this.document = document;
  }
}

final class MemoryWalletPaymentJournalStore
    implements
        WalletPaymentJournalStore,
        WalletPaymentReceiptStore,
        WalletScopedDataRemoval {
  final receiptDocuments = <String, Map<String, String>>{};
  Object? receiptWriteError;
  bool receiptCommitBeforeError = false;
  Object? removeWalletError;

  @override
  Future<void> removeWallet(String walletId) async {
    if (removeWalletError case final error?) throw error;
    documents.remove(walletId);
    receiptDocuments.remove(walletId);
  }

  @override
  Future<Map<String, String>> readAll(String walletId) async =>
      Map.unmodifiable(receiptDocuments[walletId] ?? const {});

  @override
  Future<void> writeReceipt(
    String walletId,
    String receiptKey,
    String document,
  ) async {
    if (receiptWriteError case final error? when !receiptCommitBeforeError) {
      throw error;
    }
    final wallet = receiptDocuments.putIfAbsent(walletId, () => {});
    final existing = wallet[receiptKey];
    if (existing != null && existing != document) {
      throw const StoredDataCorruptionException();
    }
    wallet[receiptKey] = document;
    if (receiptWriteError case final error?) throw error;
  }

  final documents = <String, String>{};
  final writes = <String>[];
  Object? readError;
  int? failWriteNumber;
  final Set<int> failWriteNumbers = {};
  bool commitBeforeError = false;
  final Set<int> commitBeforeErrorNumbers = {};
  void Function(String walletId, String document)? onWrite;

  @override
  Future<String?> read(String walletId) async {
    if (readError case final Object error) throw error;
    return documents[walletId];
  }

  @override
  Future<void> write(String walletId, String document) async {
    writes.add(document);
    if (writes.length == failWriteNumber ||
        failWriteNumbers.contains(writes.length)) {
      if (commitBeforeError ||
          commitBeforeErrorNumbers.contains(writes.length)) {
        documents[walletId] = document;
      }
      throw DurableStorageCommitException([
        StateError('Injected write failure'),
      ]);
    }
    documents[walletId] = document;
    onWrite?.call(walletId, document);
  }
}

final class MemoryWalletStorageSecurity
    implements WalletStorageSecurity, WalletStorageDurability {
  final flushedDirectories = <String>[];
  Object? flushError;

  @override
  Future<void> flushDirectory(String path) async {
    flushedDirectories.add(path);
    if (flushError case final error?) throw error;
  }

  final preparedRoots = <String>[];
  final createdDirectories = <String>[];
  final verifiedDirectories = <String>[];
  final verifiedFiles = <String>[];
  final replacedFiles = <String>[];
  int replaceFailuresRemaining = 0;

  @override
  Future<void> prepareRoot(String path) async {
    preparedRoots.add(path);
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> createDirectory(String path) async {
    createdDirectories.add(path);
    final directory = Directory(path);
    if (await directory.exists()) {
      throw FileSystemException('Wallet directory already exists.', path);
    }
    await directory.create();
  }

  @override
  Future<void> verifyDirectory(String path) async {
    verifiedDirectories.add(path);
    if (!await Directory(path).exists()) {
      throw FileSystemException('Wallet directory does not exist.', path);
    }
  }

  @override
  Future<void> verifyFile(String path) async {
    verifiedFiles.add(path);
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Wallet metadata file does not exist.', path);
    }
  }

  @override
  Future<void> replaceTextFile(String path, String contents) async {
    replacedFiles.add(path);
    if (replaceFailuresRemaining > 0) {
      replaceFailuresRemaining -= 1;
      throw FileSystemException('Injected metadata replacement failure.', path);
    }
    final target = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.directory) {
      throw FileSystemException('Wallet metadata target is a directory.', path);
    }
    final temporary = File('$path.memory-tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(path);
  }
}

final class FakeWalletDirectoryManager implements WalletDirectoryManager {
  final created = <String>[];
  final opened = <String>[];
  final removed = <String>[];
  final storageTokens = <String, String>{};
  Object? createError;
  bool commitCreateBeforeError = false;
  Object? openError;
  Object? removeError;

  @override
  Future<String> create(String walletId, {required String storageToken}) async {
    if (createError case final Object error) {
      if (commitCreateBeforeError) {
        created.add(walletId);
        storageTokens[walletId] = storageToken;
      }
      throw error;
    }
    created.add(walletId);
    storageTokens[walletId] = storageToken;
    return '/wallets/$walletId';
  }

  @override
  Future<String> open(String walletId, {required String storageToken}) async {
    if (openError case final Object error) throw error;
    if (storageTokens[walletId] != storageToken) {
      throw StateError('Storage token does not own this directory.');
    }
    opened.add(walletId);
    return '/wallets/$walletId';
  }

  @override
  Future<void> remove(String walletId, {required String storageToken}) async {
    if (removeError case final Object error) throw error;
    final expected = storageTokens[walletId];
    if (expected == null) return;
    if (expected != storageToken) {
      throw StateError('Storage token does not own this directory.');
    }
    removed.add(walletId);
    storageTokens.remove(walletId);
  }

  @override
  Future<Set<String>> walletIds() async => storageTokens.keys.toSet();
}

final class FakeWalletEngineFactory implements WalletEngineFactory {
  FakeWalletEngineFactory(this.engines);

  final List<FakeWalletEngine> engines;
  final configurations = <WalletEngineConfiguration>[];
  var _index = 0;

  @override
  WalletEngine create(WalletEngineConfiguration configuration) {
    configurations.add(configuration);
    return engines[_index++];
  }
}

/// In-memory native outbox shared explicitly by restart tests. App journals
/// remain a separate store so either side can lose an acknowledgement.
final class FakeWalletPaymentOperationStore {
  final Map<String, _FakeWalletPaymentOperation> _operations = {};
  final Set<String> _dispatchedOperationIds = {};

  /// Distinct payment identities, regardless of exact-operation commit replay.
  int dispatchCount = 0;

  /// Calls that could release the existing prepared transaction.
  int commitAttemptCount = 0;
  int get operationCount => _operations.length;
}

final class _FakeWalletPaymentOperation {
  _FakeWalletPaymentOperation(this.request, this.command, this.status);
  final String request;
  final WalletSendCommand? command;
  WalletPaymentRecoveryStatus status;
}

class FakeWalletEngine
    implements
        WalletEngine,
        WalletDeletionSafetyEngine,
        WalletPaymentRecoveryEngine,
        WalletPaymentDeadlineRecovery {
  FakeWalletEngine({FakeWalletPaymentOperationStore? paymentOperations})
    : paymentOperations =
          paymentOperations ?? FakeWalletPaymentOperationStore();

  final FakeWalletPaymentOperationStore paymentOperations;
  bool protectedRgbState = false;
  Object? deletionAuditError;
  Completer<void>? deletionAuditGate;

  @override
  Future<bool> hasProtectedRgbState() async {
    calls.add('deletionAudit');
    await deletionAuditGate?.future;
    if (deletionAuditError case final error?) {
      if (error is RlnOperationTimeoutException) {
        requiresPaymentReopen = true;
        throw const AppFailureException(
          AppFailure(
            code: 'wallet_deletion_audit_unavailable',
            kind: AppFailureKind.timeout,
            userMessage:
                'Wallet assets could not be checked in time. Try again.',
            retryable: true,
          ),
        );
      }
      throw error;
    }
    return protectedRgbState;
  }

  final _paymentCommands = <String, WalletSendCommand>{};
  Object? paymentOperationRequestError;
  bool paymentOperationRequestRequiresReopen = false;
  @override
  bool requiresPaymentReopen = false;
  Object? preparePaymentOperationError;
  Object? commitPaymentOperationReplyError;
  Object? inspectPaymentOperationError;
  Object? cancelPaymentOperationError;
  Object? cancelPaymentOperationReplyError;
  WalletPaymentRecoveryStatus? preparePaymentOperationResult;
  WalletPaymentRecoveryStatus? commitPaymentOperationResult;
  WalletPaymentRecoveryStatus? inspectPaymentOperationResult;
  WalletPaymentRecoveryStatus? cancelPaymentOperationResult;
  int legacySendPaymentCalls = 0;
  final calls = <String>[];
  Object? provisionError;
  Object? openPersistedError;
  Object? shutdownError;
  Object? destroyError;
  Object? syncError;
  Object? decodeInvoiceError;
  Object? createReceiveError;
  Object? sendPaymentError;
  Object? feeEstimateError;
  Object? balanceError;
  Object? activityError;
  Object? networkStatusError;
  Completer<void>? provisionGate;
  Completer<void>? openPersistedGate;
  Completer<void>? syncGate;
  Completer<void>? addressGate;
  Completer<void>? decodeInvoiceGate;
  Completer<void>? createReceiveGate;
  Completer<void>? sendPaymentGate;
  Completer<void>? feeEstimateGate;
  Completer<void>? feeEstimateStarted;
  Completer<void>? balanceGate;
  Completer<void>? activityGate;
  Completer<void>? networkStatusGate;
  String address = 'bcrt1qtest';
  String? provisionedPassword;
  String? provisionedMnemonic;
  String? openedPassword;
  WalletPaymentPreview? decodedInvoice;
  WalletReceiveRequest? createdReceiveRequest;
  WalletSendResult? sentPayment;
  WalletFeeRateEstimate? feeEstimate;
  WalletBalance? balance;
  // Opt-in adapter contract violation for defensive result validation tests.
  WalletBalance? balanceResultOverride;
  List<WalletActivity> activities = const <WalletActivity>[];
  final Map<WalletAssetId, WalletBalance> balances = {};
  PaymentRoute? decodedInvoiceRoute;
  String? decodedInvoiceValue;
  PaymentRoute? createdReceiveRoute;
  WalletAmount? createdReceiveAmount;
  WalletSendCommand? sentPaymentCommand;
  int? feeTargetBlocks;
  WalletAsset? requestedBalanceAsset;
  WalletAsset? requestedActivityAsset;
  WalletNetworkStatus? networkStatus;
  Future<WalletNetworkStatus> Function()? networkStatusReader;

  @override
  Future<void> provision({
    required String databasePassword,
    required String mnemonic,
  }) async {
    calls.add('provision');
    provisionedPassword = databasePassword;
    provisionedMnemonic = mnemonic;
    await provisionGate?.future;
    if (provisionError case final Object error) throw error;
  }

  @override
  Future<void> openPersisted({required String databasePassword}) async {
    calls.add('openPersisted');
    openedPassword = databasePassword;
    await openPersistedGate?.future;
    if (openPersistedError case final Object error) throw error;
    requiresPaymentReopen = false;
  }

  @override
  Future<void> sync() async {
    calls.add('sync');
    await syncGate?.future;
    if (syncError case final Object error) throw error;
  }

  @override
  Future<void> shutdown() async {
    calls.add('shutdown');
    if (shutdownError case final Object error) throw error;
  }

  @override
  Future<void> destroy() async {
    calls.add('destroy');
    if (destroyError case final Object error) throw error;
  }

  @override
  Future<String> getBitcoinAddress() async {
    calls.add('address:start');
    await addressGate?.future;
    calls.add('address:end');
    return address;
  }

  @override
  Future<WalletPaymentPreview> decodeInvoice(
    PaymentRoute route,
    String invoice,
  ) async {
    calls.add('decodeInvoice:start');
    decodedInvoiceRoute = route;
    decodedInvoiceValue = invoice;
    await decodeInvoiceGate?.future;
    calls.add('decodeInvoice:end');
    if (decodeInvoiceError case final Object error) throw error;
    return decodedInvoice ??
        WalletPaymentPreview(
          route: route,
          encodedDestination: invoice,
          displayDestination: invoice,
        );
  }

  @override
  Future<WalletReceiveRequest> createReceiveRequest(
    PaymentRoute route, {
    WalletAmount? amount,
  }) async {
    calls.add('createReceiveRequest:start');
    createdReceiveRoute = route;
    createdReceiveAmount = amount;
    await createReceiveGate?.future;
    calls.add('createReceiveRequest:end');
    if (createReceiveError case final Object error) throw error;
    return createdReceiveRequest ??
        WalletReceiveRequest(
          route: route,
          encodedRequest: 'request-${route.target.slug}',
          displayValue: 'request-${route.target.slug}',
          amount: amount,
        );
  }

  @override
  Future<WalletSendResult> sendPayment(WalletSendCommand command) async {
    legacySendPaymentCalls += 1;
    return _dispatchPayment(command);
  }

  Future<WalletSendResult> _dispatchPayment(WalletSendCommand command) async {
    calls.add('sendPayment:start');
    sentPaymentCommand = command;
    await sendPaymentGate?.future;
    calls.add('sendPayment:end');
    if (sendPaymentError case final Object error) throw error;
    return sentPayment ??
        WalletSendResult(
          route: command.route,
          amount: command.amount,
          referenceId: 'b' * 64,
          batchTransferIndex: command.route.asset.kind == WalletAssetKind.usdt
              ? 1
              : null,
          status: WalletPaymentStatus.pending,
        );
  }

  static String _paymentRequest(String id, WalletSendCommand command) =>
      jsonEncode({
        'version': 1,
        'id': id,
        'asset': command.route.asset.id.value,
        'precision': command.route.asset.precision,
        'rail': command.route.rail.name,
        'destination': command.destination,
        'amount': command.amount.units,
        'feeTarget': command.feeRate?.targetBlocks,
        'feeRate': command.feeRate?.satsPerVbyte,
        'feeObservedAt': command.feeRate?.observedAt.toIso8601String(),
        'feeSource': command.feeRate?.source.name,
        'rgbRecipientType': command.rgbRecipientType?.name,
        'witnessBitcoinAmountSats': command.witnessBitcoinAmountSats,
      });

  @override
  Future<String> paymentOperationRequest(
    String operationId,
    WalletSendCommand command,
  ) async {
    calls.add('paymentOperationRequest');
    if (paymentOperationRequestError case final error?) {
      if (paymentOperationRequestRequiresReopen) requiresPaymentReopen = true;
      throw error;
    }
    final request = _paymentRequest(operationId, command);
    _paymentCommands[request] = command;
    return request;
  }

  @override
  Future<void> validatePaymentOperationRequest(
    String request,
    String operationId,
    WalletSendCommand command,
  ) async {
    calls.add('validatePaymentOperationRequest');
    if (request != _paymentRequest(operationId, command)) {
      throw const StoredDataCorruptionException();
    }
  }

  String _paymentOperationId(String request) {
    final parsed = jsonDecode(request);
    if (parsed is! Map<String, Object?> || parsed['id'] is! String) {
      throw const StoredDataCorruptionException();
    }
    return parsed['id']! as String;
  }

  _FakeWalletPaymentOperation? _paymentOperation(String request) {
    final operation =
        paymentOperations._operations[_paymentOperationId(request)];
    if (operation != null && operation.request != request) {
      throw const StoredDataCorruptionException();
    }
    return operation;
  }

  @override
  Future<WalletPaymentRecoveryStatus> preparePaymentOperation(
    String request,
  ) async {
    calls.add('preparePaymentOperation');
    final existing = _paymentOperation(request);
    if (existing != null) return existing.status;
    final command = _paymentCommands[request];
    if (command == null) throw const StoredDataCorruptionException();
    if (sendPaymentError is WalletPaymentRejectedBeforeDispatchException) {
      // Preserve the existing test gate/attempt trace for a documented local
      // rejection, while creating no prepared resources or financial dispatch.
      try {
        await _dispatchPayment(command);
      } on WalletPaymentRejectedBeforeDispatchException {
        const rejected = WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.rejected,
          endAuthorized: false,
        );
        paymentOperations._operations[_paymentOperationId(request)] =
            _FakeWalletPaymentOperation(request, command, rejected);
        return rejected;
      }
      throw const StoredDataCorruptionException();
    }
    final result = sentPayment;
    final status =
        preparePaymentOperationResult ??
        WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.prepared,
          endAuthorized: false,
          referenceId: result?.referenceId ?? 'b' * 64,
          batchTransferIndex:
              result?.batchTransferIndex ??
              (command.route.asset.kind == WalletAssetKind.usdt ? 1 : null),
        );
    paymentOperations._operations[_paymentOperationId(request)] =
        _FakeWalletPaymentOperation(request, command, status);
    if (preparePaymentOperationError case final error?) throw error;
    return status;
  }

  @override
  Future<WalletPaymentRecoveryStatus> commitPaymentOperation(
    String request,
  ) async {
    calls.add('commitPaymentOperation');
    final operation = _paymentOperation(request);
    if (operation == null || operation.command == null) {
      throw const StoredDataCorruptionException();
    }
    if (operation.status.phase == WalletPaymentRecoveryPhase.accepted) {
      return operation.status;
    }
    if (commitPaymentOperationResult case final result?
        when result.phase == WalletPaymentRecoveryPhase.prepared &&
            !result.endAuthorized) {
      operation.status = result;
      return result;
    }
    final prepared = operation.status;
    operation.status = WalletPaymentRecoveryStatus(
      phase: WalletPaymentRecoveryPhase.committing,
      endAuthorized: true,
      referenceId: prepared.referenceId,
      batchTransferIndex: prepared.batchTransferIndex,
    );
    paymentOperations.commitAttemptCount += 1;
    if (paymentOperations._dispatchedOperationIds.add(
      _paymentOperationId(request),
    )) {
      paymentOperations.dispatchCount += 1;
    }
    final result = await _dispatchPayment(operation.command!);
    if (result.route != operation.command!.route ||
        result.amount != operation.command!.amount ||
        (result.status != WalletPaymentStatus.pending &&
            result.status != WalletPaymentStatus.succeeded)) {
      throw const StoredDataCorruptionException();
    }
    operation.status =
        commitPaymentOperationResult ??
        WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.accepted,
          endAuthorized: true,
          referenceId: result.referenceId,
          batchTransferIndex: result.batchTransferIndex,
        );
    if (commitPaymentOperationReplyError case final error?) throw error;
    return operation.status;
  }

  @override
  Future<WalletPaymentRecoveryStatus> inspectPaymentOperation(
    String request,
  ) async {
    calls.add('inspectPaymentOperation');
    if (inspectPaymentOperationError case final error?) throw error;
    return inspectPaymentOperationResult ??
        _paymentOperation(request)?.status ??
        const WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.absent,
          endAuthorized: false,
        );
  }

  @override
  Future<WalletPaymentRecoveryStatus> cancelPaymentOperation(
    String request,
  ) async {
    calls.add('cancelPaymentOperation');
    if (cancelPaymentOperationError case final error?) throw error;
    if (cancelPaymentOperationResult case final result?) return result;
    final existing = _paymentOperation(request);
    if (existing?.status.endAuthorized == true) return existing!.status;
    const rejected = WalletPaymentRecoveryStatus(
      phase: WalletPaymentRecoveryPhase.rejected,
      endAuthorized: false,
    );
    paymentOperations._operations[_paymentOperationId(request)] =
        _FakeWalletPaymentOperation(request, existing?.command, rejected);
    if (cancelPaymentOperationReplyError case final error?) throw error;
    return rejected;
  }

  @override
  Future<WalletBalance> getBalance(WalletAsset asset) async {
    calls.add('balance');
    requestedBalanceAsset = asset;
    await balanceGate?.future;
    if (balanceError case final Object error) throw error;
    if (balanceResultOverride case final result?) return result;
    final configured = balances[asset.id] ?? balance;
    if (configured != null) {
      if (configured.asset != asset) {
        throw StateError('Configured fake balance has a different asset.');
      }
      return configured;
    }
    WalletAmount onchain(int units) =>
        WalletAmount.onchain(assetId: asset.id, units: units);
    WalletAmount lightning(int units) =>
        WalletAmount.lightning(assetId: asset.id, units: units);
    return WalletBalance(
      asset: asset,
      onchainSettled: onchain(1),
      onchainFuture: onchain(1),
      onchainSpendable: onchain(1),
      onchainLocked: onchain(0),
      lightningOwned: lightning(0),
      lightningSpendable: lightning(0),
      lightningReceivable: lightning(0),
    );
  }

  @override
  Future<List<WalletActivity>> listActivity(WalletAsset asset) async {
    calls.add('activity');
    requestedActivityAsset = asset;
    await activityGate?.future;
    if (activityError case final Object error) throw error;
    return List<WalletActivity>.unmodifiable(activities);
  }

  @override
  Future<WalletFeeRateEstimate> estimateFeeRate(int targetBlocks) async {
    calls.add('estimateFeeRate');
    feeTargetBlocks = targetBlocks;
    if (feeEstimateStarted?.isCompleted == false) {
      feeEstimateStarted!.complete();
    }
    await feeEstimateGate?.future;
    if (feeEstimateError case final Object error) throw error;
    return feeEstimate ??
        WalletFeeRateEstimate(
          targetBlocks: targetBlocks,
          satsPerVbyte: 2,
          observedAt: DateTime.utc(2026, 8, 11),
        );
  }

  @override
  Future<WalletNetworkStatus> getNetworkStatus() async {
    calls.add('networkStatus');
    final gate = networkStatusGate;
    await gate?.future;
    if (networkStatusError case final Object error) throw error;
    if (networkStatusReader case final reader?) return reader();
    return networkStatus ??
        WalletNetworkStatus(
          environment: BlockchainEnvironment.regtest,
          blockHeight: 0,
          nodePublicKey: '020000000000000000000000000000000000000000000000000000000000000000',
          channelCount: 0,
          usableChannelCount: 0,
          peerCount: 0,
        );
  }

  Completer<void>? publicKeysGate;
  Object? publicKeysError;

  @override
  Future<WalletPublicKeys> getPublicKeys() async {
    calls.add('publicKeys');
    await publicKeysGate?.future;
    if (publicKeysError case final error?) throw error;
    return WalletPublicKeys(bitcoin: 'tpub-btc', rgb: 'tpub-rgb');
  }
}

/// Explicit capability fixture; ordinary fake/legacy engines do not advertise it.
class FakeRevocableWalletEngine extends FakeWalletEngine
    implements WalletDispatchedRgbRevocationEngine {
  FakeRevocableWalletEngine({super.paymentOperations});

  bool dispatchedRgbRevocationSupported = true;
  Object? revocationCapabilityError;
  Completer<void>? revocationGate;
  WalletPaymentRecoveryStatus? revocationResult;
  Object? revocationError;

  @override
  Future<bool> supportsDispatchedRgbRevocation() async {
    calls.add('supportsDispatchedRgbRevocation');
    if (revocationCapabilityError case final error?) throw error;
    return dispatchedRgbRevocationSupported;
  }

  @override
  Future<WalletPaymentRecoveryStatus> revokeDispatchedRgbOperation(
    String request,
  ) async {
    calls.add('revokeDispatchedRgbOperation');
    calls.add('revocation:start');
    await revocationGate?.future;
    if (revocationError case final error?) throw error;
    final operation = _paymentOperation(request);
    final result =
        revocationResult ??
        operation?.status ??
        const WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.committing,
          endAuthorized: true,
        );
    if (result.phase == WalletPaymentRecoveryPhase.accepted ||
        (result.phase == WalletPaymentRecoveryPhase.rejected &&
            !result.endAuthorized &&
            result.failureCode == 'cancelled')) {
      if (operation != null) operation.status = result;
    }
    return result;
  }
}

final class FakeWalletKeyGenerator implements WalletKeyGenerator {
  String generatedMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  Object? generationError;
  Completer<void>? generationGate;
  var generationCount = 0;
  Object? validationError;
  Completer<void>? validationGate;
  final validatedMnemonics = <String>[];
  var validationCompletionCount = 0;

  @override
  Future<String> generateMnemonic(BlockchainEnvironment environment) async {
    generationCount += 1;
    await generationGate?.future;
    if (generationError case final Object error) throw error;
    return generatedMnemonic;
  }

  @override
  Future<void> validateMnemonic(String mnemonic) async {
    validatedMnemonics.add(mnemonic);
    await validationGate?.future;
    validationCompletionCount += 1;
    if (validationError case final Object error) throw error;
  }
}

final class FakeWalletIdentityGenerator implements WalletIdentityGenerator {
  FakeWalletIdentityGenerator({
    required this.walletId,
    this.password = 'secret',
    this.storageToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  });

  final String walletId;
  final String password;
  final String storageToken;
  int _storageTokenSequence = 0;

  @override
  String newDatabasePassword() => password;

  @override
  String newStorageToken() {
    final index = _storageTokenSequence++;
    if (index == 0) return storageToken;
    return (BigInt.parse(storageToken, radix: 16) + BigInt.from(index))
        .toRadixString(16)
        .padLeft(32, '0');
  }

  @override
  String newWalletId() => walletId;
}

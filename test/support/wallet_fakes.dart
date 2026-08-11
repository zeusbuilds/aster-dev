import 'dart:async';
import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';

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

final class MemoryLegacyWalletSeedSource implements LegacyWalletSeedSource {
  final values = <String, String>{};
  Object? readError;
  var readCount = 0;

  @override
  Future<Set<String>> keys() async {
    readCount += 1;
    if (readError case final Object error) throw error;
    return values.keys.toSet();
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

final class MemoryWalletStorageSecurity implements WalletStorageSecurity {
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

final class SuccessfulLegacyWalletSeedPreflight
    implements LegacyWalletSeedPreflight {
  const SuccessfulLegacyWalletSeedPreflight();

  @override
  Future<AppResult<void>> verify() async => const AppResult.success(null);
}

final class FailingLegacyWalletSeedPreflight
    implements LegacyWalletSeedPreflight {
  const FailingLegacyWalletSeedPreflight([this.failure]);

  final AppFailure? failure;

  @override
  Future<AppResult<void>> verify() async => AppResult.failure(
    failure ??
        const AppFailure(
          code: 'wallet_recovery_required',
          kind: AppFailureKind.storage,
          userMessage: 'An older wallet must be recovered.',
          retryable: false,
        ),
  );
}

final class FakeWalletDirectoryManager implements WalletDirectoryManager {
  final created = <String>[];
  final opened = <String>[];
  final removed = <String>[];
  final storageTokens = <String, String>{};
  Object? createError;
  Object? openError;
  Object? removeError;

  @override
  Future<String> create(String walletId, {required String storageToken}) async {
    if (createError case final Object error) throw error;
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

final class FakeWalletEngine implements WalletEngine {
  final calls = <String>[];
  Object? initializeError;
  Object? reinitializeError;
  Object? shutdownError;
  Object? destroyError;
  Object? syncError;
  Object? decodeInvoiceError;
  Object? createReceiveError;
  Object? sendPaymentError;
  Object? feeEstimateError;
  Completer<void>? initializeGate;
  Completer<void>? addressGate;
  Completer<void>? decodeInvoiceGate;
  Completer<void>? createReceiveGate;
  Completer<void>? sendPaymentGate;
  String address = 'bcrt1qtest';
  String? initializedPassword;
  String? initializedMnemonic;
  WalletPaymentPreview? decodedInvoice;
  WalletReceiveRequest? createdReceiveRequest;
  WalletSendResult? sentPayment;
  WalletFeeRateEstimate? feeEstimate;
  PaymentRoute? decodedInvoiceRoute;
  String? decodedInvoiceValue;
  PaymentRoute? createdReceiveRoute;
  WalletAmount? createdReceiveAmount;
  WalletSendCommand? sentPaymentCommand;
  int? feeTargetBlocks;

  @override
  Future<void> initialize({
    required String databasePassword,
    String? mnemonic,
  }) async {
    calls.add('initialize');
    initializedPassword = databasePassword;
    initializedMnemonic = mnemonic;
    await initializeGate?.future;
    if (initializeError case final Object error) throw error;
  }

  @override
  Future<void> reinitialize({required String databasePassword}) async {
    calls.add('reinitialize');
    if (reinitializeError case final Object error) throw error;
  }

  @override
  Future<void> sync() async {
    calls.add('sync');
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
    calls.add('sendPayment:start');
    sentPaymentCommand = command;
    await sendPaymentGate?.future;
    calls.add('sendPayment:end');
    if (sendPaymentError case final Object error) throw error;
    return sentPayment ??
        WalletSendResult(
          route: command.route,
          amount: command.amount,
          referenceId: 'payment-reference',
          status: WalletPaymentStatus.pending,
        );
  }

  @override
  Future<WalletBalance> getBalance(WalletAsset asset) async {
    calls.add('balance');
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
  Future<WalletFeeRateEstimate> estimateFeeRate(int targetBlocks) async {
    calls.add('estimateFeeRate');
    feeTargetBlocks = targetBlocks;
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
    return WalletNetworkStatus(
      environment: BlockchainEnvironment.regtest,
      blockHeight: 0,
      nodePublicKey:
          '020000000000000000000000000000000000000000000000000000000000000000',
      channelCount: 0,
      usableChannelCount: 0,
      peerCount: 0,
    );
  }

  @override
  Future<WalletPublicKeys> getPublicKeys() async {
    calls.add('publicKeys');
    return WalletPublicKeys(bitcoin: 'tpub-btc', rgb: 'tpub-rgb');
  }
}

final class FakeWalletKeyGenerator implements WalletKeyGenerator {
  String generatedMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  Object? generationError;
  Object? validationError;
  Completer<void>? validationGate;
  final validatedMnemonics = <String>[];
  var validationCompletionCount = 0;

  @override
  Future<String> generateMnemonic(BlockchainEnvironment environment) async {
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

  @override
  String newDatabasePassword() => password;

  @override
  String newStorageToken() => storageToken;

  @override
  String newWalletId() => walletId;
}

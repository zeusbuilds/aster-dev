import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/wallet_fakes.dart';

void main() {
  const walletId = '11111111111111111111111111111111';
  const secondWalletId = '22222222222222222222222222222222';
  const storageToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const secondStorageToken = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const services = WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
  );

  test('publishes four targets and fails closed for unconfigured USDT', () {
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      _FailingRegistrationStore(),
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    expect(
      repository.paymentCapabilities.map((item) => item.target),
      WalletPaymentTarget.values,
    );
    expect(repository.paymentCapabilities.map((item) => item.isAvailable), [
      true,
      true,
      false,
      false,
    ]);
    final result = repository.resolvePaymentTarget(
      WalletPaymentTarget.usdtOnchain,
    );
    expect(result, isA<AppFailureResult<PaymentRoute>>());
    expect(
      (result as AppFailureResult<PaymentRoute>).failure.code,
      'rgb_usdt_not_configured',
    );
  });

  test('resolves configured USDT from immutable deployment identity', () {
    const configured = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      usdtAsset: RgbAssetConfiguration(
        contractId: 'rgb:configured-usdt',
        precision: 6,
      ),
    );
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      configured,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      _FailingRegistrationStore(),
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      configured,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = repository.resolvePaymentTarget(
      WalletPaymentTarget.usdtLightning,
    );

    expect(result, isA<AppSuccess<PaymentRoute>>());
    final route = (result as AppSuccess<PaymentRoute>).value;
    expect(route.asset.id.value, 'rgb:configured-usdt');
    expect(route.asset.precision, 6);
    expect(route.rail, PaymentRail.lightning);
  });

  test(
    'loads a configured cross-rail portfolio in one repository turn',
    () async {
      const configured = WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        usdtAsset: RgbAssetConfiguration(
          contractId: 'rgb:configured-usdt',
          precision: 6,
        ),
      );
      final harness = await _createActiveRepository(services: configured);
      addTearDown(harness.runtime.dispose);

      final result = await harness.repository.portfolio();

      expect(result, isA<AppSuccess<WalletPortfolio>>());
      final portfolio = (result as AppSuccess<WalletPortfolio>).value;
      expect(portfolio.bitcoin.asset, WalletAsset.bitcoin);
      expect(portfolio.usdt?.asset.id.value, 'rgb:configured-usdt');
      expect(portfolio.usdt?.asset.precision, 6);
      expect(
        harness.engine.calls.where((call) => call == 'balance'),
        hasLength(2),
      );
    },
  );

  test(
    'omits USDT portfolio balance when deployment metadata is absent',
    () async {
      final harness = await _createActiveRepository();
      addTearDown(harness.runtime.dispose);

      final result = await harness.repository.portfolio();

      expect(result, isA<AppSuccess<WalletPortfolio>>());
      final portfolio = (result as AppSuccess<WalletPortfolio>).value;
      expect(portfolio.usdt, isNull);
      expect(
        harness.engine.calls.where((call) => call == 'balance'),
        hasLength(1),
      );
    },
  );

  test('loads activity balance and records in one repository turn', () async {
    final engine = FakeWalletEngine();
    engine.activities = <WalletActivity>[
      WalletActivity(
        id: 'activity-${'a' * 64}',
        source: WalletActivitySource.bitcoinTransaction,
        operation: WalletActivityOperation.bitcoinReceive,
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.onchain,
        direction: WalletActivityDirection.received,
        status: WalletActivityStatus.succeeded,
        amount: WalletAmount.onchain(
          assetId: WalletAsset.bitcoin.id,
          units: 10,
        ),
        occurredAt: DateTime.utc(2026, 8, 11),
        txid: 'activity-txid',
      ),
    ];
    final harness = await _createActiveRepository(engine: engine);
    addTearDown(harness.runtime.dispose);

    final result = await harness.repository.activityFeed(
      WalletAssetKind.bitcoin,
    );

    expect(result, isA<AppSuccess<WalletActivityFeed>>());
    final feed = (result as AppSuccess<WalletActivityFeed>).value;
    expect(feed.activities, engine.activities);
    expect(feed.networkStatus.blockHeight, 0);
    expect(engine.requestedBalanceAsset, WalletAsset.bitcoin);
    expect(engine.requestedActivityAsset, WalletAsset.bitcoin);
    expect(
      engine.calls.where(
        (call) =>
            call == 'networkStatus' || call == 'balance' || call == 'activity',
      ),
      ['networkStatus', 'balance', 'activity'],
    );
  });

  test('fails before native activity when USDT is not configured', () async {
    final harness = await _createActiveRepository();
    addTearDown(harness.runtime.dispose);

    final result = await harness.repository.activityFeed(WalletAssetKind.usdt);

    expect(result, isA<AppFailureResult<WalletActivityFeed>>());
    expect(harness.engine.calls, isNot(contains('activity')));
  });

  test('previews onchain locally and validates invoice input', () async {
    final harness = await _createActiveRepository();
    addTearDown(harness.runtime.dispose);

    final onchain = await harness.repository.previewPayment(
      WalletPaymentTarget.bitcoinOnchain,
      'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
    );
    final malformed = await harness.repository.previewPayment(
      WalletPaymentTarget.bitcoinLightning,
      ' lnbcrt1invoice ',
    );

    expect(onchain, isA<AppSuccess<WalletPaymentPreview>>());
    expect(
      (onchain as AppSuccess<WalletPaymentPreview>).value.encodedDestination,
      'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
    );
    expect(malformed, isA<AppFailureResult<WalletPaymentPreview>>());
    expect(
      (malformed as AppFailureResult<WalletPaymentPreview>).failure.code,
      'bitcoin_lightning_instruction_invalid',
    );
    expect(harness.engine.calls, isNot(contains('decodeInvoice:start')));
  });

  test('extracts BIP321 Lightning before native preview validation', () async {
    final harness = await _createActiveRepository();
    addTearDown(harness.runtime.dispose);

    final result = await harness.repository.previewPayment(
      WalletPaymentTarget.bitcoinLightning,
      'bitcoin:?lightning=lnbcrt1invoice&label=Merchant&message=Order%20123',
    );

    expect(result, isA<AppSuccess<WalletPaymentPreview>>());
    final preview = (result as AppSuccess<WalletPaymentPreview>).value;
    expect(harness.engine.decodedInvoiceValue, 'lnbcrt1invoice');
    expect(preview.encodedDestination, 'lnbcrt1invoice');
    expect(preview.recipientLabel, 'Merchant');
    expect(preview.message, 'Order 123');
  });

  test('passes deployment-owned route and exact units to receive', () async {
    const configured = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      usdtAsset: RgbAssetConfiguration(
        contractId: 'rgb:configured-usdt',
        precision: 6,
      ),
    );
    final harness = await _createActiveRepository(services: configured);
    addTearDown(harness.runtime.dispose);

    final result = await harness.repository.createReceiveRequest(
      WalletPaymentTarget.usdtLightning,
      amountUnits: 1250000,
    );

    expect(result, isA<AppSuccess<WalletReceiveRequest>>());
    expect(
      harness.engine.createdReceiveRoute?.target,
      WalletPaymentTarget.usdtLightning,
    );
    expect(
      harness.engine.createdReceiveRoute?.asset.id.value,
      'rgb:configured-usdt',
    );
    expect(harness.engine.createdReceiveAmount?.units, 1250000);
    expect(
      harness.engine.createdReceiveAmount?.unit,
      WalletAmountUnit.assetAtomic,
    );
  });

  test(
    'rejects invalid receive amounts without invoking native code',
    () async {
      final harness = await _createActiveRepository();
      addTearDown(harness.runtime.dispose);

      final result = await harness.repository.createReceiveRequest(
        WalletPaymentTarget.bitcoinLightning,
        amountUnits: 0,
      );

      expect(result, isA<AppFailureResult<WalletReceiveRequest>>());
      expect(
        (result as AppFailureResult<WalletReceiveRequest>).failure.code,
        'payment_amount_invalid',
      );
      expect(
        harness.engine.calls,
        isNot(contains('createReceiveRequest:start')),
      );
    },
  );

  test('refreshes a displayed fee inside every onchain send', () async {
    final observedAt = DateTime.now().toUtc();
    final engine = FakeWalletEngine()
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 3,
        observedAt: observedAt,
      );
    final harness = await _createActiveRepository(engine: engine);
    addTearDown(harness.runtime.dispose);

    final estimateResult = await harness.repository.estimateFeeRate();
    expect(estimateResult, isA<AppSuccess<WalletFeeRateEstimate>>());
    final estimate =
        (estimateResult as AppSuccess<WalletFeeRateEstimate>).value;
    expect(estimate.satsPerVbyte, 3);
    expect(engine.feeTargetBlocks, 6);

    engine.feeEstimate = WalletFeeRateEstimate(
      targetBlocks: 6,
      satsPerVbyte: 4,
      observedAt: observedAt,
    );
    final sent = await harness.repository.sendPayment(
      target: WalletPaymentTarget.bitcoinOnchain,
      destination: 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
      amountUnits: 1,
    );
    engine.feeEstimateError = const RlnOperationTimeoutException(
      operation: 'estimateFeeRate',
      timeout: Duration(seconds: 30),
    );
    final failedRefresh = await harness.repository.sendPayment(
      target: WalletPaymentTarget.bitcoinOnchain,
      destination: 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
      amountUnits: 1,
    );
    final invalidTarget = await harness.repository.estimateFeeRate(
      targetBlocks: 0,
    );

    expect(sent, isA<AppSuccess<WalletSendResult>>());
    expect(engine.sentPaymentCommand?.feeRate?.satsPerVbyte, 4);
    expect(
      (failedRefresh as AppFailureResult<WalletSendResult>).failure.code,
      'wallet_operation_outcome_unknown',
    );
    expect(
      (invalidTarget as AppFailureResult<WalletFeeRateEstimate>).failure.code,
      'payment_fee_target_invalid',
    );
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
    expect(
      engine.calls.where((call) => call == 'estimateFeeRate'),
      hasLength(3),
    );
  });

  test('submits an exact typed command and maps native failures', () async {
    final engine = FakeWalletEngine();
    final harness = await _createActiveRepository(engine: engine);
    addTearDown(harness.runtime.dispose);

    final sent = await harness.repository.sendPayment(
      target: WalletPaymentTarget.bitcoinLightning,
      destination: 'bitcoin:?lightning=lnbcrt1invoice',
      amountUnits: 21000,
    );

    expect(sent, isA<AppSuccess<WalletSendResult>>());
    expect(
      engine.sentPaymentCommand?.route.target,
      WalletPaymentTarget.bitcoinLightning,
    );
    expect(engine.sentPaymentCommand?.amount.units, 21000);
    expect(engine.sentPaymentCommand?.destination, 'lnbcrt1invoice');
    expect(
      engine.sentPaymentCommand?.amount.unit,
      WalletAmountUnit.millisatoshi,
    );

    engine.decodeInvoiceError = const NativeProtocolException(
      'Malformed native invoice.',
      field: 'invoice',
    );
    final decoded = await harness.repository.previewPayment(
      WalletPaymentTarget.bitcoinLightning,
      'lnbcrt1malformed',
    );
    expect(decoded, isA<AppFailureResult<WalletPaymentPreview>>());
    expect(
      (decoded as AppFailureResult<WalletPaymentPreview>).failure.code,
      'native_protocol_error',
    );
  });

  test('normalizes BIP321 fallback and enforces its encoded amount', () async {
    final harness = await _createActiveRepository();
    addTearDown(harness.runtime.dispose);
    const address = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';

    final sent = await harness.repository.sendPayment(
      target: WalletPaymentTarget.bitcoinOnchain,
      destination: 'bitcoin:$address?amount=0.00000100&label=Merchant',
      amountUnits: 100,
    );
    final mismatch = await harness.repository.sendPayment(
      target: WalletPaymentTarget.bitcoinOnchain,
      destination: 'bitcoin:$address?amount=0.00000100',
      amountUnits: 101,
    );

    expect(sent, isA<AppSuccess<WalletSendResult>>());
    expect(harness.engine.sentPaymentCommand?.destination, address);
    expect(harness.engine.sentPaymentCommand?.amount.units, 100);
    expect(mismatch, isA<AppFailureResult<WalletSendResult>>());
    expect(
      (mismatch as AppFailureResult<WalletSendResult>).failure.code,
      'payment_amount_mismatch',
    );
    expect(
      harness.engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
  });

  test('rejects invalid sends without invoking native code', () async {
    final harness = await _createActiveRepository();
    addTearDown(harness.runtime.dispose);

    final invalidAmount = await harness.repository.sendPayment(
      target: WalletPaymentTarget.bitcoinOnchain,
      destination: 'bcrt1qdestination',
      amountUnits: 0,
    );
    final invalidDestination = await harness.repository.sendPayment(
      target: WalletPaymentTarget.bitcoinOnchain,
      destination: ' bcrt1qdestination ',
      amountUnits: 1,
    );

    expect(invalidAmount, isA<AppFailureResult<WalletSendResult>>());
    expect(invalidDestination, isA<AppFailureResult<WalletSendResult>>());
    expect(harness.engine.calls, isNot(contains('sendPayment:start')));
    expect(harness.engine.calls, isNot(contains('estimateFeeRate')));
  });

  test('serializes payment operations through the repository owner', () async {
    final engine = FakeWalletEngine()..decodeInvoiceGate = Completer<void>();
    final harness = await _createActiveRepository(engine: engine);
    addTearDown(harness.runtime.dispose);

    final decoding = harness.repository.previewPayment(
      WalletPaymentTarget.bitcoinLightning,
      'lnbcrt1invoice',
    );
    final receiving = harness.repository.createReceiveRequest(
      WalletPaymentTarget.bitcoinOnchain,
      amountUnits: 100,
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.calls, contains('decodeInvoice:start'));
    expect(engine.calls, isNot(contains('createReceiveRequest:start')));

    engine.decodeInvoiceGate!.complete();
    expect(await decoding, isA<AppSuccess<WalletPaymentPreview>>());
    expect(await receiving, isA<AppSuccess<WalletReceiveRequest>>());
    expect(
      engine.calls.indexOf('decodeInvoice:end'),
      lessThan(engine.calls.indexOf('createReceiveRequest:start')),
    );
  });

  test('normalizes and validates every generated recovery phrase', () async {
    final keyGenerator = FakeWalletKeyGenerator()
      ..generatedMnemonic =
          '  ABANDON abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon ABOUT  ';
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      _FailingRegistrationStore(),
      runtime,
      keyGenerator,
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.generateMnemonic();

    expect(result, isA<AppSuccess<String>>());
    expect(
      (result as AppSuccess<String>).value,
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about',
    );
    expect(keyGenerator.validatedMnemonics, [result.value]);
  });

  test(
    'rejects malformed recovery material returned by the generator',
    () async {
      final keyGenerator = FakeWalletKeyGenerator()
        ..generatedMnemonic = 'not twelve words';
      final runtime = WalletRuntime(
        FakeWalletEngineFactory(const []),
        FakeWalletDirectoryManager(),
        WalletSecretStore(MemorySecureStore()),
        services,
      );
      addTearDown(runtime.dispose);
      final repository = WalletRepository(
        _FailingRegistrationStore(),
        runtime,
        keyGenerator,
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const SuccessfulLegacyWalletSeedPreflight(),
      );

      final result = await repository.generateMnemonic();

      expect(result, isA<AppFailureResult<String>>());
      expect(
        (result as AppFailureResult<String>).failure.code,
        'wallet_mnemonic_generation_invalid',
      );
      expect(keyGenerator.validatedMnemonics, isEmpty);
    },
  );

  test('normalizes and validates an imported recovery phrase', () async {
    final keyGenerator = FakeWalletKeyGenerator();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      _FailingRegistrationStore(),
      runtime,
      keyGenerator,
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.validateMnemonic(
      '  ABANDON abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon ABOUT  ',
    );

    expect(result, isA<AppSuccess<void>>());
    expect(keyGenerator.validatedMnemonics, [mnemonic]);
  });

  test('rejects malformed or checksum-invalid imported phrases', () async {
    final keyGenerator = FakeWalletKeyGenerator();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      _FailingRegistrationStore(),
      runtime,
      keyGenerator,
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final malformed = await repository.validateMnemonic('too short');
    expect(malformed, isA<AppFailureResult<void>>());
    expect(
      (malformed as AppFailureResult<void>).failure.code,
      'wallet_mnemonic_invalid',
    );
    expect(keyGenerator.validatedMnemonics, isEmpty);

    keyGenerator.validationError = const AppFailureException(
      AppFailure(
        code: 'native_phrase_invalid',
        kind: AppFailureKind.validation,
        userMessage: 'Not rendered.',
        retryable: false,
      ),
    );
    final checksum = await repository.validateMnemonic(
      List.filled(12, 'abandon').join(' '),
    );
    expect(checksum, isA<AppFailureResult<void>>());
    expect(
      (checksum as AppFailureResult<void>).failure.code,
      'wallet_mnemonic_invalid',
    );
  });

  test('commits metadata only after native provisioning succeeds', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final profileStore = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      PreferencesService(preferences),
    );
    final rawSecrets = MemorySecureStore();
    final engine = FakeWalletEngine();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.createFromMnemonic(
      mnemonic:
          '  ABANDON abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon ABOUT  ',
      name: '  Main Wallet  ',
    );

    final committed = (result as AppSuccess<WalletRegistry>).value;
    final profile = committed.activeProfile!;
    expect(profile.name, 'Main Wallet');
    expect(profile.state, WalletProfileState.ready);
    expect(engine.initializedMnemonic, mnemonic);
    final registry =
        (await profileStore.read() as AppSuccess<WalletRegistry>).value;
    expect(registry.activeWalletId, walletId);
    expect(rawSecrets.values, hasLength(1));
  });

  test('rolls back native data when metadata commit fails', () async {
    final profileStore = _FailingRegistrationStore();
    final rawSecrets = MemorySecureStore();
    final directories = FakeWalletDirectoryManager();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([FakeWalletEngine()]),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.createFromMnemonic(
      mnemonic: mnemonic,
      name: 'Main Wallet',
    );

    expect(result, isA<AppFailureResult<WalletRegistry>>());
    expect(rawSecrets.values, isEmpty);
    expect(directories.removed, [walletId]);
  });

  test(
    'preserves resources and quarantines runtime when commit is unknown',
    () async {
      final profileStore = _FailingRegistrationStore(outcomeUnknown: true);
      final rawSecrets = MemorySecureStore();
      final directories = FakeWalletDirectoryManager();
      final engine = FakeWalletEngine();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([engine]),
        directories,
        WalletSecretStore(rawSecrets),
        services,
      );
      addTearDown(runtime.dispose);
      final repository = WalletRepository(
        profileStore,
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const SuccessfulLegacyWalletSeedPreflight(),
      );

      final result = await repository.createFromMnemonic(
        mnemonic: mnemonic,
        name: 'Main Wallet',
      );

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.outcomeUnknown,
        isTrue,
      );
      expect(rawSecrets.values, hasLength(1));
      expect(directories.storageTokens, contains(walletId));
      expect(directories.removed, isEmpty);
      expect(engine.calls, contains('destroy'));
      expect(runtime.snapshot.phase, WalletRuntimePhase.disposed);
    },
  );

  test('stages uncertain credential writes for startup recovery', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final documents = MemoryWalletRegistryDocumentStore();
    final profileStore = WalletProfileStore(
      documents,
      PreferencesService(preferences),
    );
    final key = 'utexo_wallet_secret_v2.$walletId';
    final rawSecrets = MemorySecureStore()
      ..writeError = StateError('injected write response failure')
      ..commitWriteBeforeError = true
      ..readErrors[key] = StateError('injected verification failure');
    final directories = FakeWalletDirectoryManager();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );
    addTearDown(repository.dispose);

    final result = await repository.createFromMnemonic(
      mnemonic: mnemonic,
      name: 'Main Wallet',
    );
    final staged =
        (await profileStore.read() as AppSuccess<WalletRegistry>).value;

    expect(result, isA<AppFailureResult<WalletRegistry>>());
    expect(
      (result as AppFailureResult<WalletRegistry>).failure.outcomeUnknown,
      isTrue,
    );
    expect(staged.provisioningProfiles, hasLength(1));
    expect(rawSecrets.values, hasLength(1));
    expect(directories.storageTokens, contains(walletId));

    rawSecrets
      ..writeError = null
      ..readErrors.clear();
    expect(await repository.bootstrap(), isA<AppSuccess<WalletRegistry>>());
    final recovered =
        (await profileStore.read() as AppSuccess<WalletRegistry>).value;
    expect(recovered.profiles, isEmpty);
    expect(rawSecrets.values, isEmpty);
    expect(directories.storageTokens, isEmpty);
  });

  test('wallet ID collision cannot overwrite an existing wallet', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final profileStore = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      PreferencesService(preferences),
    );
    final now = DateTime.utc(2026, 8, 8);
    await profileStore.stageProvision(
      WalletProfile(
        id: walletId,
        name: 'Existing',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: storageToken,
      ),
    );
    await profileStore.commitProvision(walletId);
    final rawSecrets = MemorySecureStore();
    const existingSecret = WalletSecret(
      databasePassword: 'existing-password',
      mnemonic: 'existing mnemonic',
      storageToken: storageToken,
    );
    await WalletSecretStore(rawSecrets).write(walletId, existingSecret);
    final directories = FakeWalletDirectoryManager();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.createFromMnemonic(
      mnemonic: mnemonic,
      name: 'New Wallet',
    );

    expect(result, isA<AppFailureResult<WalletRegistry>>());
    expect(
      (result as AppFailureResult<WalletRegistry>).failure.code,
      'wallet_id_collision',
    );
    expect(directories.created, isEmpty);
    final retained = (await WalletSecretStore(rawSecrets).read(
      walletId,
      expectedStorageToken: storageToken,
    ) as AppSuccess<WalletSecret>).value;
    expect(retained.databasePassword, existingSecret.databasePassword);
  });

  test(
    'bootstrap stops before profile access when migration is required',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final documents = MemoryWalletRegistryDocumentStore()
        ..document = '{corrupt';
      final runtime = WalletRuntime(
        FakeWalletEngineFactory(const []),
        FakeWalletDirectoryManager(),
        WalletSecretStore(MemorySecureStore()),
        services,
      );
      addTearDown(runtime.dispose);
      final repository = WalletRepository(
        WalletProfileStore(documents, PreferencesService(preferences)),
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const FailingLegacyWalletSeedPreflight(),
      );

      final result = await repository.bootstrap();

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.code,
        'wallet_recovery_required',
      );
      expect(documents.readCount, 0);
    },
  );

  test('bootstrap rolls back an interrupted staged wallet', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final profileStore = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      PreferencesService(preferences),
    );
    final now = DateTime.utc(2026, 8, 8);
    await profileStore.stageProvision(
      WalletProfile(
        id: walletId,
        name: 'Interrupted',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: storageToken,
      ),
    );
    final rawSecrets = MemorySecureStore();
    await WalletSecretStore(rawSecrets).write(
      walletId,
      const WalletSecret(
        databasePassword: 'password',
        mnemonic: 'mnemonic words',
        storageToken: storageToken,
      ),
    );
    final directories = FakeWalletDirectoryManager()
      ..storageTokens[walletId] = storageToken;
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.bootstrap();

    final snapshot = (result as AppSuccess<WalletRegistry>).value;
    expect(snapshot.profiles, isEmpty);
    expect(rawSecrets.values, isEmpty);
    expect(directories.removed, [walletId]);
  });

  test(
    'bootstrap fails closed when current wallet resources are orphaned',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final rawSecrets = MemorySecureStore();
      await WalletSecretStore(rawSecrets).write(
        walletId,
        const WalletSecret(
          databasePassword: 'password',
          mnemonic: mnemonic,
          storageToken: storageToken,
        ),
      );
      final runtime = WalletRuntime(
        FakeWalletEngineFactory(const []),
        FakeWalletDirectoryManager(),
        WalletSecretStore(rawSecrets),
        services,
      );
      addTearDown(runtime.dispose);
      final repository = WalletRepository(
        WalletProfileStore(
          MemoryWalletRegistryDocumentStore(),
          PreferencesService(preferences),
        ),
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const SuccessfulLegacyWalletSeedPreflight(),
      );

      final result = await repository.bootstrap();

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.code,
        'wallet_storage_recovery_required',
      );
      expect(rawSecrets.values, hasLength(1));
    },
  );

  test('selected metadata reopens a missing native runtime', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final profileStore = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      PreferencesService(preferences),
    );
    final now = DateTime.utc(2026, 8, 8);
    final profile = WalletProfile(
      id: walletId,
      name: 'Main',
      createdAt: now,
      updatedAt: now,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.provisioning,
      storageToken: storageToken,
    );
    await profileStore.stageProvision(profile);
    await profileStore.commitProvision(walletId);
    final secrets = MemorySecureStore();
    await WalletSecretStore(secrets).write(
      walletId,
      const WalletSecret(
        databasePassword: 'password',
        mnemonic: 'mnemonic words',
        storageToken: storageToken,
      ),
    );
    final directories = FakeWalletDirectoryManager()
      ..storageTokens[walletId] = storageToken;
    final engine = FakeWalletEngine();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      directories,
      WalletSecretStore(secrets),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.switchWallet(walletId);

    expect(result, isA<AppSuccess<WalletRegistry>>());
    expect(runtime.snapshot.phase, WalletRuntimePhase.active);
    expect(engine.initializedMnemonic, isNull);
  });

  test(
    'resume reconciles a failed shutdown from durable active state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final profileStore = WalletProfileStore(
        MemoryWalletRegistryDocumentStore(),
        PreferencesService(preferences),
      );
      final active = FakeWalletEngine();
      final recovered = FakeWalletEngine();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([active, recovered]),
        FakeWalletDirectoryManager(),
        WalletSecretStore(MemorySecureStore()),
        services,
      );
      addTearDown(runtime.dispose);
      final repository = WalletRepository(
        profileStore,
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const SuccessfulLegacyWalletSeedPreflight(),
      );
      expect(
        await repository.createFromMnemonic(
          mnemonic: mnemonic,
          name: 'Main Wallet',
        ),
        isA<AppSuccess<WalletRegistry>>(),
      );
      active.shutdownError = StateError('injected shutdown failure');

      expect(await repository.suspend(), isA<AppFailureResult<void>>());
      final result = await repository.resume();

      expect(result, isA<AppSuccess<void>>());
      expect(active.calls, containsAllInOrder(['shutdown', 'destroy']));
      expect(recovered.initializedMnemonic, isNull);
      expect(runtime.snapshot.phase, WalletRuntimePhase.active);
      expect(runtime.snapshot.walletId, walletId);
    },
  );

  test(
    'quarantines a switched runtime when selection commit is unknown',
    () async {
      final now = DateTime.utc(2026, 8, 8);
      final firstProfile = WalletProfile(
        id: walletId,
        name: 'First',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.ready,
        storageToken: storageToken,
      );
      final secondProfile = WalletProfile(
        id: secondWalletId,
        name: 'Second',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.ready,
        storageToken: secondStorageToken,
      );
      final profiles = _FailingSwitchStore(
        WalletRegistry(
          profiles: [firstProfile, secondProfile],
          activeWalletId: walletId,
        ),
      );
      final firstEngine = FakeWalletEngine();
      final secondEngine = FakeWalletEngine();
      final secrets = MemorySecureStore();
      final directories = FakeWalletDirectoryManager();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([firstEngine, secondEngine]),
        directories,
        WalletSecretStore(secrets),
        services,
      );
      addTearDown(runtime.dispose);
      await runtime.provision(
        profile: WalletProfile(
          id: walletId,
          name: 'First',
          createdAt: now,
          updatedAt: now,
          environment: BlockchainEnvironment.regtest,
          state: WalletProfileState.provisioning,
          storageToken: storageToken,
        ),
        mnemonic: 'first mnemonic',
        databasePassword: 'first-password',
      );
      await WalletSecretStore(secrets).write(
        secondWalletId,
        const WalletSecret(
          databasePassword: 'second-password',
          mnemonic: 'second mnemonic',
          storageToken: secondStorageToken,
        ),
      );
      directories.storageTokens[secondWalletId] = secondStorageToken;
      final repository = WalletRepository(
        profiles,
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const SuccessfulLegacyWalletSeedPreflight(),
      );

      final result = await repository.switchWallet(secondWalletId);

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.outcomeUnknown,
        isTrue,
      );
      expect(runtime.snapshot.phase, WalletRuntimePhase.disposed);
      expect(firstEngine.calls, contains('destroy'));
      expect(secondEngine.calls, contains('destroy'));
      expect(
        directories.storageTokens.keys,
        containsAll([walletId, secondWalletId]),
      );
      expect(secrets.values, hasLength(2));
    },
  );

  test('wallet reads stay ordered behind a requested wallet switch', () async {
    final now = DateTime.utc(2026, 8, 8);
    final firstProfile = WalletProfile(
      id: walletId,
      name: 'First',
      createdAt: now,
      updatedAt: now,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.ready,
      storageToken: storageToken,
    );
    final secondProfile = WalletProfile(
      id: secondWalletId,
      name: 'Second',
      createdAt: now,
      updatedAt: now,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.ready,
      storageToken: secondStorageToken,
    );
    final profiles = _GatedProfileStore(
      WalletRegistry(
        profiles: [firstProfile, secondProfile],
        activeWalletId: walletId,
      ),
    );
    final firstEngine = FakeWalletEngine();
    final secondEngine = FakeWalletEngine();
    final secrets = MemorySecureStore();
    final directories = FakeWalletDirectoryManager();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([firstEngine, secondEngine]),
      directories,
      WalletSecretStore(secrets),
      services,
    );
    addTearDown(runtime.dispose);
    await runtime.provision(
      profile: WalletProfile(
        id: walletId,
        name: 'First',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: storageToken,
      ),
      mnemonic: 'first mnemonic',
      databasePassword: 'first-password',
    );
    await WalletSecretStore(secrets).write(
      secondWalletId,
      const WalletSecret(
        databasePassword: 'second-password',
        mnemonic: 'second mnemonic',
        storageToken: secondStorageToken,
      ),
    );
    directories.storageTokens[secondWalletId] = secondStorageToken;
    final repository = WalletRepository(
      profiles,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final switching = repository.switchWallet(secondWalletId);
    await Future<void>.delayed(Duration.zero);
    final balance = repository.balance(WalletAssetKind.bitcoin);
    await Future<void>.delayed(Duration.zero);

    expect(firstEngine.calls, isNot(contains('balance')));
    expect(secondEngine.calls, isNot(contains('balance')));

    profiles.releaseRead();
    expect(await switching, isA<AppSuccess<WalletRegistry>>());
    expect(await balance, isA<AppSuccess<WalletBalance>>());
    expect(firstEngine.calls, isNot(contains('balance')));
    expect(secondEngine.calls, contains('balance'));
  });
}

final class _ActiveRepositoryHarness {
  const _ActiveRepositoryHarness({
    required this.repository,
    required this.runtime,
    required this.engine,
  });

  final WalletRepository repository;
  final WalletRuntime runtime;
  final FakeWalletEngine engine;
}

Future<_ActiveRepositoryHarness> _createActiveRepository({
  WalletServiceConfiguration services = const WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
  ),
  FakeWalletEngine? engine,
}) async {
  const walletId = '11111111111111111111111111111111';
  const storageToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final selectedEngine = engine ?? FakeWalletEngine();
  final runtime = WalletRuntime(
    FakeWalletEngineFactory([selectedEngine]),
    FakeWalletDirectoryManager(),
    WalletSecretStore(MemorySecureStore()),
    services,
  );
  final provisioned = await runtime.provision(
    profile: WalletProfile(
      id: walletId,
      name: 'Active',
      createdAt: DateTime.utc(2026, 8, 11),
      updatedAt: DateTime.utc(2026, 8, 11),
      environment: services.environment,
      state: WalletProfileState.provisioning,
      storageToken: storageToken,
    ),
    mnemonic: 'test mnemonic',
    databasePassword: 'test-password',
  );
  if (provisioned is! AppSuccess<void>) {
    throw StateError('Test wallet runtime did not provision.');
  }
  return _ActiveRepositoryHarness(
    repository: WalletRepository(
      _FailingRegistrationStore(),
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    ),
    runtime: runtime,
    engine: selectedEngine,
  );
}

final class _FailingRegistrationStore implements WalletProfilePersistence {
  _FailingRegistrationStore({this.outcomeUnknown = false});

  final bool outcomeUnknown;
  var snapshot = WalletRegistry(profiles: const [], activeWalletId: null);

  @override
  Future<AppResult<WalletRegistry>> read() async => AppResult.success(snapshot);

  @override
  Future<AppResult<WalletRegistry>> stageProvision(
    WalletProfile profile,
  ) async {
    snapshot = WalletRegistry(profiles: [profile], activeWalletId: null);
    return AppResult.success(snapshot);
  }

  @override
  Future<AppResult<WalletRegistry>> commitProvision(String walletId) async =>
      AppResult.failure(
        AppFailure(
          code: 'test_registration_failed',
          kind: AppFailureKind.storage,
          userMessage: 'Could not save wallet.',
          retryable: false,
          outcomeUnknown: outcomeUnknown,
        ),
      );

  @override
  Future<AppResult<WalletRegistry>> remove(String walletId) async {
    snapshot = WalletRegistry(profiles: const [], activeWalletId: null);
    return AppResult.success(snapshot);
  }

  @override
  Future<AppResult<WalletRegistry>> setActive(String walletId) async =>
      AppResult.success(snapshot);
}

final class _GatedProfileStore implements WalletProfilePersistence {
  _GatedProfileStore(this.snapshot);

  WalletRegistry snapshot;
  final _readGate = Completer<void>();

  void releaseRead() {
    if (!_readGate.isCompleted) _readGate.complete();
  }

  @override
  Future<AppResult<WalletRegistry>> read() async {
    await _readGate.future;
    return AppResult.success(snapshot);
  }

  @override
  Future<AppResult<WalletRegistry>> setActive(String walletId) async {
    snapshot = WalletRegistry(
      profiles: snapshot.profiles,
      activeWalletId: walletId,
    );
    return AppResult.success(snapshot);
  }

  @override
  Future<AppResult<WalletRegistry>> commitProvision(String walletId) =>
      throw UnimplementedError();

  @override
  Future<AppResult<WalletRegistry>> remove(String walletId) =>
      throw UnimplementedError();

  @override
  Future<AppResult<WalletRegistry>> stageProvision(WalletProfile profile) =>
      throw UnimplementedError();
}

final class _FailingSwitchStore implements WalletProfilePersistence {
  _FailingSwitchStore(this.snapshot);

  final WalletRegistry snapshot;

  @override
  Future<AppResult<WalletRegistry>> read() async => AppResult.success(snapshot);

  @override
  Future<AppResult<WalletRegistry>> setActive(String walletId) async =>
      AppResult.failure(
        const AppFailure(
          code: 'test_switch_commit_unknown',
          kind: AppFailureKind.storage,
          userMessage: 'Could not confirm wallet selection.',
          retryable: false,
          outcomeUnknown: true,
        ),
      );

  @override
  Future<AppResult<WalletRegistry>> commitProvision(String walletId) =>
      throw UnimplementedError();

  @override
  Future<AppResult<WalletRegistry>> remove(String walletId) =>
      throw UnimplementedError();

  @override
  Future<AppResult<WalletRegistry>> stageProvision(WalletProfile profile) =>
      throw UnimplementedError();
}

import 'dart:async';
import 'dart:convert';

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/bootstrap/app_loader.dart';
import 'package:aster/core/core.dart';
import 'package:aster/features/market/presentation/models/models.dart';
import 'package:aster/features/market/presentation/view_model/view_models.dart';
import 'package:aster/features/onboarding/presentation/screens/screens.dart';
import 'package:aster/features/settings/data/repository/repository.dart';
import 'package:aster/features/settings/presentation/screens/screens.dart';
import 'package:aster/features/shell/presentation/providers/app_shell_index_provider.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/pages/pages.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/main.dart' show AsterApp;
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/payment_flow_harness.dart'
    show PaymentSettingsAssetBundle;
import '../../support/presentation_fakes.dart';
import '../../support/scan_fakes.dart';
import '../../support/wallet_fakes.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'DM Sans',
    )..addFont(rootBundle.load('assets/fonts/DMSans-Variable.ttf'))).load();
  });

  for (final protectedRgb in [true, false]) {
    testWidgets(
      'Settings-tab push retains one ${protectedRgb ? 'RGB refusal warning' : 'audit failure'} after native auth',
      (tester) async {
        final h = await _FeedbackHarness.create(
          tester,
          protectedRgb: protectedRgb,
          auditError: protectedRgb
              ? null
              : StateError('Fixture audit unavailable'),
          startFromHome: true,
        );
        addTearDown(() => h.dispose(tester));
        await h.pump(tester);
        expect(find.byType(WalletDetailsScreen), findsOneWidget);
        await _delete(tester, h);

        final current = h.container.read(toastControllerProvider).current;
        expect(current?.title, 'Wallet not deleted');
        expect(
          current?.variant,
          protectedRgb ? ToastVariant.warning : ToastVariant.failure,
        );
        expect(find.text(current!.message!), findsOneWidget);
        expect(h.container.read(toastControllerProvider).pending, isEmpty);
        expect(h.container.read(appShellIndexProvider), 3);
        await _expectWalletRetained(h);
        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();
        final detailsRow = find.widgetWithText(
          AsterOptionRow,
          'Wallet details',
        );
        expect(detailsRow, findsOneWidget);
        expect(
          tester.widget<AsterOptionRow>(detailsRow).onTap,
          isNotNull,
          reason: 'Returning from a refused deletion must release Settings navigation.',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'production RGB deletion refusal is visible once after native auth',
    (tester) async {
      final h = await _FeedbackHarness.create(tester, protectedRgb: true);
      addTearDown(() => h.dispose(tester));
      await h.pump(tester);
      await _delete(tester, h);

      final current = h.container.read(toastControllerProvider).current;
      expect(current?.title, 'Wallet not deleted');
      expect(current?.variant, ToastVariant.warning);
      expect(
        current?.message,
        'Send all USDT/RGB assets and finish pending requests before deleting this wallet.',
      );
      expect(h.container.read(toastControllerProvider).pending, isEmpty);
      expect(find.text(current!.message!), findsOneWidget);
      expect(find.byType(WalletDetailsScreen), findsOneWidget);
      expect(
        h.container.read(walletViewModelProvider).value?.operationFailure,
        isNull,
      );
      expect(h.container.read(appShellIndexProvider), 3);
      expect(h.engine.calls, contains('deletionAudit'));
      expect(h.engine.calls, isNot(contains('destroy')));
      await _expectWalletRetained(h);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('production native audit failure is visible after native auth', (
    tester,
  ) async {
    final h = await _FeedbackHarness.create(
      tester,
      auditError: StateError('Fixture audit unavailable'),
    );
    addTearDown(() => h.dispose(tester));
    await h.pump(tester);
    await _delete(tester, h);

    final current = h.container.read(toastControllerProvider).current;
    expect(current?.title, 'Wallet not deleted');
    expect(current?.variant, ToastVariant.failure);
    expect(current?.message, isNotEmpty);
    expect(h.container.read(toastControllerProvider).pending, isEmpty);
    expect(find.text(current!.message!), findsOneWidget);
    expect(find.byType(WalletDetailsScreen), findsOneWidget);
    expect(
      h.container.read(walletViewModelProvider).value?.operationFailure,
      isNull,
    );
    expect(h.container.read(appShellIndexProvider), 3);
    expect(h.engine.calls, isNot(contains('destroy')));
    await _expectWalletRetained(h);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Bitcoin balance alone does not cause a silent refusal', (
    tester,
  ) async {
    final h = await _FeedbackHarness.create(tester);
    addTearDown(() => h.dispose(tester));
    h.engine.balance = _bitcoinBalance(10000000);
    await h.pump(tester);
    await _delete(tester, h);

    final registry = await h.profiles.read();
    expect((registry as AppSuccess<WalletRegistry>).value.profiles, isEmpty);
    expect(find.byType(OnboardingWelcomeScreen), findsOneWidget);
    expect(find.byType(WalletDetailsScreen), findsNothing);
    expect(h.container.read(toastControllerProvider).current, isNull);
    expect(h.engine.calls, contains('destroy'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'corrupt pending-payment evidence leaves a deliberate blocking route',
    (tester) async {
      final h = await _FeedbackHarness.create(tester);
      addTearDown(() => h.dispose(tester));
      await h.pump(tester);
      h.journals.documents[_firstId] = 'not-json';
      await _delete(tester, h);

      expect(h.container.read(walletViewModelProvider).hasError, isTrue);
      expect(find.byType(WalletAccessScreen), findsOneWidget);
      expect(find.byType(WalletDetailsScreen), findsNothing);
      expect(find.text('Wallet access unavailable'), findsOneWidget);
      expect(h.engine.calls, isNot(contains('deletionAudit')));
      expect(h.engine.calls, isNot(contains('destroy')));
      await _expectWalletRetained(h);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an unresolved native payment refusal reaches the access gate rather than silently staying in details',
    (tester) async {
      final h = await _FeedbackHarness.create(tester);
      addTearDown(() => h.dispose(tester));
      await h.pump(tester);
      final now = DateTime.now().toUtc();
      const route = PaymentRoute(
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.onchain,
      );
      final command = WalletSendCommand(
        route: route,
        destination: 'bcrt1qpublic-fixture',
        amount: WalletAmount.onchain(
          assetId: WalletAsset.bitcoin.id,
          units: 20000,
        ),
        feeRate: WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: now,
        ),
      );
      final request = await h.engine.paymentOperationRequest('a' * 32, command);
      h.journals.documents[_firstId] = jsonEncode({
        'version': 3,
        'commitAttempted': true,
        'recoveryRequest': request,
        'id': 'a' * 32,
        'walletId': _firstId,
        'storageToken': _first.storageToken,
        'network': 'regtest',
        'submittedAt': now.toIso8601String(),
        'phase': 'submitting',
        'command': {
          'asset': 'bitcoin',
          'precision': 8,
          'destination': command.destination,
          'amount': 20000,
          'feeTarget': 6,
          'feeRate': 2,
          'feeObservedAt': now.toIso8601String(),
          'feeSource': 'networkEstimate',
          'rgbRecipientType': null,
          'witnessBitcoinAmountSats': null,
        },
        'result': null,
      });
      // This only stages public in-memory evidence; no payment is dispatched.
      await _delete(tester, h);

      final state = h.container.read(walletViewModelProvider);
      expect(state.hasError, isTrue);
      expect(
        (state.error! as AppFailureException).failure.code,
        'payment_submission_unresolved',
      );
      expect(find.byType(WalletAccessScreen), findsOneWidget);
      expect(find.byType(WalletDetailsScreen), findsNothing);
      expect(find.text('Wallet access unavailable'), findsOneWidget);
      expect(h.engine.calls, isNot(contains('deletionAudit')));
      expect(h.engine.calls, isNot(contains('destroy')));
      await _expectWalletRetained(h);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _delete(WidgetTester tester, _FeedbackHarness h) async {
  await tester.tap(find.widgetWithText(CustomButton, 'Delete wallet'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(CustomButton, 'Delete'));
  await tester.pump(const Duration(milliseconds: 400));
  expect(h.deletePrompts, 1);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await tester.pump();
  h.deleteReply.complete('authenticated');
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

Future<void> _expectWalletRetained(_FeedbackHarness h) async {
  final registry = await h.profiles.read();
  expect(
    (registry as AppSuccess<WalletRegistry>).value.profiles.single.id,
    _firstId,
  );
}

WalletBalance _bitcoinBalance(int units) {
  final available = WalletAmount.onchain(
    assetId: const WalletAssetId.bitcoin(),
    units: units,
  );
  final zero = WalletAmount.onchain(
    assetId: const WalletAssetId.bitcoin(),
    units: 0,
  );
  final lightning = WalletAmount.lightning(
    assetId: const WalletAssetId.bitcoin(),
    units: 0,
  );
  return WalletBalance(
    asset: WalletAsset.bitcoin,
    onchainSettled: available,
    onchainFuture: available,
    onchainSpendable: available,
    onchainLocked: zero,
    lightningOwned: lightning,
    lightningSpendable: lightning,
    lightningReceivable: lightning,
  );
}

const _firstId = '11111111111111111111111111111111';
const _secondId = '22222222222222222222222222222222';
final _first = _profile(_firstId, 'First wallet');
final _second = _profile(_secondId, 'Second wallet');
WalletProfile _profile(String id, String name) => WalletProfile(
  id: id,
  name: name,
  createdAt: DateTime.utc(2026, 10, 26),
  updatedAt: DateTime.utc(2026, 10, 26),
  environment: BlockchainEnvironment.regtest,
  state: WalletProfileState.ready,
  storageToken: id,
);

final class _FeedbackHarness {
  static const channel = MethodChannel('aster.test.delete_native_order');
  final deleteReply = Completer<String>();
  final finalStatusGate = Completer<void>();
  bool finalStatusHeld = false;
  bool _deleteReplied = false;
  int deletePrompts = 0;
  bool _startFromHome = false;
  late final FakeWalletEngine engine;
  final journals = MemoryWalletPaymentJournalStore();
  late final SecurityController security;
  late final WalletProfileStore profiles;
  late final WalletRepository repository;
  late final ProviderContainer container;
  ProviderSubscription<GoRouter>? _routerLease;

  static Future<_FeedbackHarness> create(
    WidgetTester tester, {
    bool holdFinalStatus = false,
    bool protectedRgb = false,
    Object? auditError,
    bool includeSecondWallet = false,
    bool startFromHome = false,
  }) async {
    final h = _FeedbackHarness();
    h._startFromHome = startFromHome;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'getStatus':
          if (holdFinalStatus && h._deleteReplied && !h.finalStatusHeld) {
            h.finalStatusHeld = true;
            await h.finalStatusGate.future;
          }
          return {'secured': true, 'captured': false};
        case 'authenticate':
          final arguments = call.arguments as Map<Object?, Object?>;
          if (arguments['reason'] != 'Delete this wallet') {
            return 'authenticated';
          }
          h.deletePrompts++;
          final result = await h.deleteReply.future;
          h._deleteReplied = true;
          return result;
        case 'cancel':
        case 'setSensitive':
          return null;
        default:
          throw StateError('Unexpected fixture method ${call.method}');
      }
    });
    final device = PlatformDeviceAuthentication(channel: channel);
    h.security = SecurityController(device);
    await h.security.initialize(hasWallet: true);
    h.security.updateWallet(_firstId);
    await h.security.unlock();
    // This plugin's mock backend and every wallet store are process-local.
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final documents = MemoryWalletRegistryDocumentStore();
    h.profiles = WalletProfileStore(documents);
    final secrets = WalletSecretStore(MemorySecureStore());
    final directories = FakeWalletDirectoryManager();
    for (final fixture in [_first, if (includeSecondWallet) _second]) {
      final staged = fixture.copyWith(state: WalletProfileState.provisioning);
      expect(
        await h.profiles.stageProvision(staged),
        isA<AppSuccess<WalletRegistry>>(),
      );
      expect(
        await h.profiles.commitProvision(staged.id),
        isA<AppSuccess<WalletRegistry>>(),
      );
      expect(
        await secrets.write(
          staged.id,
          WalletSecret(
            databasePassword: 'public-fixture-password',
            mnemonic: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
            storageToken: staged.storageToken,
          ),
        ),
        isA<AppSuccess<void>>(),
      );
      directories.storageTokens[staged.id] = staged.storageToken;
    }
    expect(
      await h.profiles.setActive(_firstId),
      isA<AppSuccess<WalletRegistry>>(),
    );
    const services = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
    );
    h.engine = FakeWalletEngine()
      ..protectedRgbState = protectedRgb
      ..deletionAuditError = auditError;
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([
        h.engine,
        ...List.generate(9, (_) => FakeWalletEngine()),
      ]),
      directories,
      secrets,
      services,
    );
    h.repository = WalletRepository(
      h.profiles,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: '3' * 32),
      services,
      securityController: h.security,
      paymentJournalStore: h.journals,
      paymentReceiptStore: h.journals,
    );
    h.container = ProviderContainer(
      retry: applicationProviderRetryPolicy,
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => preferences),
        securityControllerProvider.overrideWithValue(h.security),
        walletRepositoryProvider.overrideWith((ref) async => h.repository),
        walletRuntimeProvider.overrideWith((ref) async => runtime),
        walletServiceConfigurationProvider.overrideWithValue(services),
        settingsRepositoryProvider.overrideWith(
          (ref) async => SettingsRepository(
            PreferencesService(preferences),
            PaymentSettingsAssetBundle(),
          ),
        ),
        appMetadataServiceProvider.overrideWithValue(const _NativeMetadata()),
        hapticFeedbackServiceProvider.overrideWithValue(
          RecordingHapticFeedbackService(),
        ),
        bitcoinMarketViewModelProvider.overrideWith(_NoNetworkMarket.new),
        scanSessionFactoryProvider.overrideWithValue(
          QueueScanSessionFactory([FakeScanSession()]),
        ),
      ],
    );
    await bootstrapApplicationContainer(h.container);
    h._routerLease = h.container.listen(appRouterProvider, (_, _) {});
    // Normal navigation enters Wallet details from the Settings tab. Preserve
    // that nonzero tab scope across auth and failed deletion responses.
    h.container.read(appShellIndexProvider.notifier).setIndex(3);
    h.container
        .read(appRouterProvider)
        .goNamed(startFromHome ? RouteNames.home : RouteNames.walletDetails);
    return h;
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      AppLoader(
        security: security,
        initialize: () async => container,
        child: const AsterApp(),
      ),
    );
    await tester.pump();
    // AppLoader deliberately delays reveal before starting its animation.
    // pumpAndSettle alone stops before that timer's first animation frame.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    if (_startFromHome) {
      final row = find.widgetWithText(AsterOptionRow, 'Wallet details');
      await tester.ensureVisible(row);
      expect(row.hitTestable(), findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    final disposal = repository.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    _routerLease?.close();
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump();
    }
    await disposal;
    security.dispose();
    channel.setMethodCallHandler(null);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  Future<void> sendNativeEvent(WidgetTester tester, MethodCall call) async {
    final delivered = Completer<void>();
    // Exercise the production adapter's native-to-Dart event handler.
    // ignore: deprecated_member_use
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(call),
      (_) => delivered.complete(),
    );
    await delivered.future;
  }
}

final class _NativeMetadata implements AppMetadataService {
  const _NativeMetadata();
  @override
  Future<AppResult<AppBuildMetadata>> load() async => const AppResult.success(
    AppBuildMetadata(version: '0.2.0-test', buildNumber: '1'),
  );
}

final class _NoNetworkMarket extends BitcoinMarketViewModel {
  @override
  Future<BitcoinMarketState> build() async =>
      const BitcoinMarketState(snapshot: null);

  @override
  Future<void> retry() async {}
}

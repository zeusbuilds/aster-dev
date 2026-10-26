import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/core/security/security_gate.dart';
import 'package:aster/features/settings/presentation/screens/screens.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/presentation_fakes.dart';
import '../../support/wallet_fakes.dart';

void main() {
  test(
    'disclosures require one fresh purpose-bound wallet grant per read',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(
        await h.repository.publicKeys(walletId: _id),
        isA<AppFailureResult<WalletPublicKeys>>(),
      );
      expect(
        await h.repository.recoveryMnemonic(_id),
        isA<AppFailureResult<String>>(),
      );
      final export = await h.security.authorize(
        SecurityPurpose.exportXpubs,
        walletId: _id,
      );
      expect(
        await h.repository.recoveryMnemonic(_id, authorization: export),
        isA<AppFailureResult<String>>(),
      );
      expect(
        await h.repository.publicKeys(walletId: _id, authorization: export),
        isA<AppSuccess<WalletPublicKeys>>(),
      );
      expect(
        await h.repository.publicKeys(walletId: _id, authorization: export),
        isA<AppFailureResult<WalletPublicKeys>>(),
      );
      final seed = await h.security.authorize(
        SecurityPurpose.revealSeed,
        walletId: _id,
      );
      expect(
        (await h.repository.recoveryMnemonic(
          _id,
          authorization: seed,
        ) as AppSuccess<String>).value,
        _fixturePhrase,
      );
      expect(h.device.prompts, 2);
    },
  );

  test(
    'queued wallet work and disclosure cannot dispatch after locking',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final grant = await h.security.authorize(
        SecurityPurpose.exportXpubs,
        walletId: _id,
      );
      final gate = Completer<void>();
      h.engine.networkStatusGate = gate;
      final inFlight = h.repository.networkStatus();
      await Future<void>.delayed(Duration.zero);
      final queued = h.repository.publicKeys(
        walletId: _id,
        authorization: grant,
      );
      h.security.lock();
      gate.complete();
      expect(await inFlight, isA<AppSuccess<WalletNetworkStatus>>());
      expect(await queued, isA<AppFailureResult<WalletPublicKeys>>());
      expect(h.engine.calls, isNot(contains('publicKeys')));
      // Lifecycle cleanup must remain possible behind the lock.
      expect(await h.repository.suspend(), isA<AppSuccess<void>>());
      expect(await h.repository.load(), isA<AppSuccess<WalletRegistry>>());
    },
  );

  test(
    'unsecured devices bypass every native prompt but retain scope checks',
    () async {
      final h = await _Harness.create(secured: false);
      addTearDown(h.dispose);
      final grant = await h.security.authorize(
        SecurityPurpose.exportXpubs,
        walletId: _id,
      );
      expect(
        await h.repository.publicKeys(walletId: _id, authorization: grant),
        isA<AppSuccess<WalletPublicKeys>>(),
      );
      final seed = await h.security.authorize(
        SecurityPurpose.revealSeed,
        walletId: _id,
      );
      expect(
        await h.repository.recoveryMnemonic(_id, authorization: seed),
        isA<AppSuccess<String>>(),
      );
      expect(h.device.prompts, 0);
      h.security.lock();
      expect(h.security.isLocked, isFalse);
    },
  );

  test(
    'App lock off still requires fresh native auth for a disclosure',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.security.setAppLockEnabled(false), isTrue);
      final grant = await h.security.authorize(
        SecurityPurpose.exportXpubs,
        walletId: _id,
      );
      expect(
        await h.repository.publicKeys(walletId: _id, authorization: grant),
        isA<AppSuccess<WalletPublicKeys>>(),
      );
      expect(h.device.prompts, 2);
    },
  );

  testWidgets(
    'Security has device lock status, confirmation and one system-auth change',
    (tester) async {
      final h = await _Harness.create();
      addTearDown(() => _cleanup(tester, h));
      await h.pump(tester, securitySettings: true);
      expect(find.text('Lock automatically'), findsNothing);
      expect(find.text('Immediately'), findsNothing);
      expect(find.text('On'), findsOneWidget);
      final toggle = find.byKey(const ValueKey('security-app-lock-switch'));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Turn off App lock?'), findsOneWidget);
      expect(h.device.prompts, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.security.appLockEnabled, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(h.security.appLockEnabled, isFalse);
      expect(h.device.prompts, 1);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('unsecured settings show Off and never offer a false lock', (
    tester,
  ) async {
    final h = await _Harness.create(secured: false);
    addTearDown(() => _cleanup(tester, h));
    await h.pump(tester, securitySettings: true);
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('security-app-lock-switch')),
    );
    expect(toggle.value, isFalse);
    expect(toggle.onChanged, isNull);
    final lock = tester.widget<AsterOptionRow>(
      find.byKey(const ValueKey('security-lock-now')),
    );
    expect(lock.onTap, isNull);
    expect(find.text('Lock automatically'), findsNothing);
    expect(find.text('Off'), findsOneWidget);
    expect(h.device.prompts, 0);
  });

  testWidgets('native auth must finish before reading or showing xpubs', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => _cleanup(tester, h));
    h.device.nextPrompt = Completer<DeviceAuthenticationResult>();
    await h.pump(tester);
    await tester.tap(find.text('Export xpubs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('tpub-btc'), findsNothing);
    expect(h.engine.calls, isNot(contains('publicKeys')));
    h.device.nextPrompt!.complete(DeviceAuthenticationResult.authenticated);
    await tester.pumpAndSettle();
    expect(find.text('tpub-btc'), findsOneWidget);
    expect(find.text('tpub-rgb'), findsOneWidget);
    expect(find.text('Fixture wallet'), findsNothing);
    final explanation = find.text(
      'Extended public keys can reveal your wallet activity. Share them only with services you trust.',
    );
    final copy = find.widgetWithText(CustomButton, 'Copy');
    final share = find.widgetWithText(CustomButton, 'Share');
    final explanationBounds = tester.getRect(explanation);
    final copyBounds = tester.getRect(copy);
    final shareBounds = tester.getRect(share);
    final screenBounds = tester.getRect(find.byType(Scaffold).last);
    expect(
      explanationBounds.top,
      greaterThan(tester.getRect(find.text('tpub-rgb')).bottom),
    );
    expect(explanationBounds.bottom, lessThanOrEqualTo(copyBounds.top));
    expect(copyBounds.top - explanationBounds.bottom, lessThan(64));
    expect(copyBounds.top, shareBounds.top);
    expect(
      copyBounds.bottom,
      greaterThan(screenBounds.top + screenBounds.height * 0.8),
    );
    expect(h.device.prompts, 1);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(
      h.clipboard.text,
      'Bitcoin account\ntpub-btc\n\nRGB account\ntpub-rgb',
    );
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(h.share.sharedText, h.clipboard.text);
    expect(h.share.sharedOrigin?.isValid, isTrue);
  });

  for (final revealSeed in [false, true]) {
    testWidgets(
      '${revealSeed ? 'seed' : 'xpub'} own-auth success continues before SecurityGate rebuilds after resume',
      (tester) async {
        final h = await _Harness.create();
        addTearDown(() => _cleanup(tester, h));
        h.device.nextPrompt = Completer<DeviceAuthenticationResult>();
        await h.pump(tester, gated: true);
        await tester.tap(
          find.text(revealSeed ? 'Reveal seed phrase' : 'Export xpubs'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(h.device.prompts, 1);
        await _completeOwnPromptBeforeGateFrame(
          tester,
          h,
          route: find.byType(WalletDisclosureScreen, skipOffstage: false),
        );
        if (!revealSeed) expect(h.engine.calls, contains('publicKeys'));
        await tester.pumpAndSettle();
        expect(find.text(revealSeed ? 'alpha' : 'tpub-btc'), findsOneWidget);
        expect(find.text('Advanced'), findsNothing);
        expect(h.device.prompts, 1);
        expect(h.toasts.messages, isEmpty);
      },
    );
  }

  testWidgets(
    'App lock off and on continue before SecurityGate rebuilds after own-auth resume',
    (tester) async {
      final h = await _Harness.create();
      addTearDown(() => _cleanup(tester, h));
      await h.pump(tester, securitySettings: true, gated: true);
      final toggle = find.byKey(const ValueKey('security-app-lock-switch'));
      h.device.nextPrompt = Completer<DeviceAuthenticationResult>();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(h.device.prompts, 1);
      await _completeOwnPromptBeforeGateFrame(
        tester,
        h,
        route: find.byType(SecuritySettingsScreen, skipOffstage: false),
      );
      expect(h.security.appLockEnabled, isFalse);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      h.device.nextPrompt = Completer<DeviceAuthenticationResult>();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(h.device.prompts, 2);
      await _completeOwnPromptBeforeGateFrame(
        tester,
        h,
        route: find.byType(SecuritySettingsScreen, skipOffstage: false),
      );
      expect(h.security.appLockEnabled, isTrue);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(h.toasts.messages, isEmpty);
    },
  );

  testWidgets(
    'capture at entry gives one action response before auth or reads',
    (tester) async {
      final h = await _Harness.create();
      addTearDown(() => _cleanup(tester, h));
      h.device.capture(true);
      await h.pump(tester);
      await tester.tap(find.text('Export xpubs'));
      await tester.pumpAndSettle();
      expect(find.text('Advanced'), findsOneWidget);
      expect(h.device.prompts, 0);
      expect(h.device.protections, isEmpty);
      expect(h.engine.calls, isNot(contains('publicKeys')));
      expect(h.toasts.messages, hasLength(1));
      expect(
        h.toasts.messages.single.message,
        'Stop screen sharing to view wallet information.',
      );
    },
  );

  testWidgets(
    'a disclosure opened while locked waits for unlock and then reauthenticates',
    (tester) async {
      final h = await _Harness.create();
      addTearDown(() => _cleanup(tester, h));
      h.security.lock();
      await h.pump(tester);
      await tester.tap(find.text('Export xpubs'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.device.prompts, 0);
      expect(h.engine.calls, isNot(contains('publicKeys')));
      expect(find.text('tpub-btc'), findsNothing);
      expect(await h.security.unlock(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('tpub-btc'), findsOneWidget);
      expect(h.device.prompts, 2);
      expect(h.toasts.messages, isEmpty);
    },
  );

  testWidgets(
    'leaving a deferred disclosure cancels its wait without late reads',
    (tester) async {
      final h = await _Harness.create();
      addTearDown(() => _cleanup(tester, h));
      h.security.lock();
      await h.pump(tester);
      await tester.tap(find.text('Export xpubs'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      h.router!.pop();
      await tester.pumpAndSettle();
      expect(await h.security.unlock(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Advanced'), findsOneWidget);
      expect(h.device.prompts, 1);
      expect(h.engine.calls, isNot(contains('publicKeys')));
    },
  );

  testWidgets('cancel returns to Advanced silently without reading keys', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => _cleanup(tester, h));
    h.device.result = DeviceAuthenticationResult.cancelled;
    await h.pump(tester);
    await tester.tap(find.text('Export xpubs'));
    await tester.pumpAndSettle();
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Reveal seed phrase'), findsOneWidget);
    expect(h.engine.calls, isNot(contains('publicKeys')));
    expect(h.toasts.messages, isEmpty);
  });

  testWidgets(
    'native failures return one toast to the action, never inline prose',
    (tester) async {
      final h = await _Harness.create();
      addTearDown(() => _cleanup(tester, h));
      h.device.error = StateError('fixture OS unavailable');
      await h.pump(tester);
      await tester.tap(find.text('Export xpubs'));
      await tester.pumpAndSettle();
      expect(find.text('Advanced'), findsOneWidget);
      expect(h.toasts.messages, hasLength(1));
      expect(h.toasts.messages.single.title, 'Wallet information unavailable');
      expect(
        find.textContaining('Device authentication is unavailable'),
        findsNothing,
      );
      expect(h.engine.calls, isNot(contains('publicKeys')));
    },
  );

  for (final captured in [false, true]) {
    testWidgets(
      '${captured ? 'capture' : 'background'} clears seed words and returning requires new auth',
      (tester) async {
        final h = await _Harness.create();
        addTearDown(() => _cleanup(tester, h));
        await h.pump(tester);
        await tester.tap(find.text('Reveal seed phrase'));
        await tester.pumpAndSettle();
        expect(find.text('alpha'), findsOneWidget);
        expect(find.text('Fixture wallet'), findsNothing);
        expect(
          tester
              .getRect(
                find.text(
                  'Keep these words private. Anyone with them can access your funds.',
                ),
              )
              .top,
          greaterThan(tester.getRect(find.text('mu')).bottom),
        );
        expect(find.text('Copy'), findsNothing);
        expect(find.text('Share'), findsNothing);
        if (captured) {
          h.device.capture(true);
        } else {
          h.security.handleLifecycle(AppLifecycleState.paused);
        }
        await tester.pumpAndSettle();
        expect(find.text('alpha'), findsNothing);
        expect(find.text('Advanced'), findsOneWidget);
        if (captured) {
          h.device.capture(false);
        } else {
          h.security.handleLifecycle(AppLifecycleState.resumed);
          await h.security.unlock();
        }
        final prompts = h.device.prompts;
        await tester.tap(find.text('Reveal seed phrase'));
        await tester.pumpAndSettle();
        expect(find.text('alpha'), findsOneWidget);
        expect(h.device.prompts, prompts + 1);
      },
    );
  }

  testWidgets(
    'a covered disclosure clears and exits on return without closing the newer page',
    (tester) async {
      final h = await _Harness.create();
      addTearDown(() => _cleanup(tester, h));
      await h.pump(tester);
      await tester.tap(find.text('Reveal seed phrase'));
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);
      unawaited(h.router!.push<void>('/other'));
      await tester.pumpAndSettle();
      expect(find.text('Other page'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
      h.router!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Advanced'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
    },
  );

  testWidgets('wallet switch discards visible phrase immediately', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => _cleanup(tester, h));
    await h.pump(tester);
    await tester.tap(find.text('Reveal seed phrase'));
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);
    h.wallet.publish(WalletState());
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsNothing);
    expect(find.text('Advanced'), findsOneWidget);
  });
}

/// Deliberately complete the native response after the controller is resumed
/// while the rendered gate still has Offstage/TickerMode from the inactive
/// frame. A successful action may not treat that stale widget value as a
/// departure, return silently, or ask for another native prompt.
Future<void> _completeOwnPromptBeforeGateFrame(
  WidgetTester tester,
  _Harness harness, {
  required Finder route,
}) async {
  harness.security.handleLifecycle(AppLifecycleState.inactive);
  await tester.pump();
  final element = route.evaluate().single;
  expect(TickerMode.valuesOf(element).enabled, isFalse);
  harness.security.handleLifecycle(AppLifecycleState.resumed);
  harness.device.nextPrompt!.complete(DeviceAuthenticationResult.authenticated);
  for (var turn = 0; turn < 64; turn++) {
    await Future<void>.value();
  }
  expect(harness.security.isAuthenticating, isFalse);
  expect(harness.security.canAccessWallet, isTrue);
  // No pump has happened since resume. The gate's rendered inherited state
  // must still be disabled when the continuation has already completed.
  expect(TickerMode.valuesOf(element).enabled, isFalse);
}

Future<void> _cleanup(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final disposal = harness.dispose();
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump();
  }
  await disposal;
}

const _id = '11111111111111111111111111111111';
const _token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _fixturePhrase =
    'alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu';
const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
);

class _Device implements DeviceAuthentication {
  _Device(this.securityStatus);
  DeviceSecurityStatus securityStatus;
  DeviceAuthenticationResult result = DeviceAuthenticationResult.authenticated;
  Completer<DeviceAuthenticationResult>? nextPrompt;
  Object? error;
  int prompts = 0;
  final captures = StreamController<bool>.broadcast(sync: true);
  final protections = <bool>[];
  bool _captured = false;
  @override
  bool get isCaptured => _captured;
  @override
  Stream<bool> get captureChanges => captures.stream;
  @override
  Future<DeviceSecurityStatus> status() async => securityStatus;
  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) async {
    prompts++;
    if (error != null) throw error!;
    return nextPrompt == null ? result : nextPrompt!.future;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> setSensitive(bool value) async => protections.add(value);
  void capture(bool value) {
    _captured = value;
    captures.add(value);
  }
}

class _Wallet extends WalletViewModel {
  _Wallet(this.profile);
  final WalletProfile profile;
  @override
  Future<WalletState> build() async =>
      WalletState(wallets: [profile], activeWallet: profile);
  void publish(WalletState next) => state = AsyncData(next);
}

class _Harness {
  final engine = FakeWalletEngine();
  final clipboard = MemoryClipboardService();
  final share = RecordingShareService();
  final toasts = RecordingToastPresentationService();
  final haptics = RecordingHapticFeedbackService();
  late final _Device device;
  late final SecurityController security;
  late final WalletRuntime runtime;
  late final WalletRepository repository;
  late final _Wallet wallet;
  ProviderContainer? container;
  GoRouter? router;

  static Future<_Harness> create({bool secured = true}) async {
    final h = _Harness();
    h.device = _Device(
      secured ? DeviceSecurityStatus.secured : DeviceSecurityStatus.unsecured,
    );
    h.security = SecurityController(h.device);
    await h.security.initialize(hasWallet: true);
    h.security.updateWallet(_id);
    if (h.security.isLocked) await h.security.unlock();
    h.device.prompts = 0;
    final profile = WalletProfile(
      id: _id,
      name: 'Fixture wallet',
      createdAt: DateTime.utc(2026, 10, 25),
      updatedAt: DateTime.utc(2026, 10, 25),
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.provisioning,
      storageToken: _token,
    );
    h.runtime = WalletRuntime(
      FakeWalletEngineFactory([h.engine]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      _services,
    );
    final provisioned = await h.runtime.provision(
      profile: profile,
      mnemonic: _fixturePhrase,
      databasePassword: 'fixture-only',
    );
    expect(provisioned, isA<AppSuccess<void>>());
    final profiles = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      clock: () => DateTime.utc(2026, 10, 25),
    );
    await profiles.stageProvision(profile);
    final ready =
        await profiles.commitProvision(_id) as AppSuccess<WalletRegistry>;
    h.wallet = _Wallet(ready.value.activeProfile!);
    h.repository = WalletRepository(
      profiles,
      h.runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: _id),
      _services,
      securityController: h.security,
    );
    return h;
  }

  Future<void> pump(
    WidgetTester tester, {
    bool securitySettings = false,
    bool gated = false,
  }) async {
    container = ProviderContainer(
      overrides: [
        securityControllerProvider.overrideWithValue(security),
        walletRepositoryProvider.overrideWith((ref) async => repository),
        walletViewModelProvider.overrideWith(() => wallet),
        clipboardServiceProvider.overrideWithValue(clipboard),
        shareServiceProvider.overrideWithValue(share),
      ],
    );
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => securitySettings
              ? const SecuritySettingsScreen()
              : const AdvancedSettingsScreen(),
          routes: [
            GoRoute(
              path: 'other',
              builder: (_, _) => const Scaffold(body: Text('Other page')),
            ),
            GoRoute(
              path: 'seed',
              name: RouteNames.revealSeed,
              builder: (_, _) => const WalletDisclosureScreen.seed(),
            ),
            GoRoute(
              path: 'xpubs',
              name: RouteNames.exportXpubs,
              builder: (_, _) => const WalletDisclosureScreen.xpubs(),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container!,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router!,
          builder: (context, child) => AsterFeedbackScope(
            haptics: haptics,
            toasts: toasts,
            child: gated
                ? SecurityGate(controller: security, child: child!)
                : child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    router?.dispose();
    container?.dispose();
    await repository.dispose();
    security.dispose();
    await device.captures.close();
  }
}

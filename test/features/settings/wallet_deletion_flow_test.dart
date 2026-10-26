import 'dart:async';

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/bootstrap/app_loader.dart';
import 'package:aster/core/core.dart';
import 'package:aster/core/security/security_gate.dart';
import 'package:aster/features/onboarding/presentation/screens/screens.dart';
import 'package:aster/features/settings/data/repository/repository.dart';
import 'package:aster/features/settings/presentation/screens/screens.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/main.dart' show AsterApp;
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/payment_flow_harness.dart'
    show PaymentSettingsAssetBundle;
import '../../support/presentation_fakes.dart';
import '../../support/wallet_fakes.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'DM Sans',
    )..addFont(rootBundle.load('assets/fonts/DMSans-Variable.ttf'))).load();
  });

  testWidgets('cancelling deletion never authenticates or changes the wallet', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => h.dispose(tester));
    await h.pump(tester);

    await _openConfirmation(tester);
    final cancel = find.widgetWithText(CustomButton, 'Cancel');
    final confirm = find.widgetWithText(CustomButton, 'Delete');
    expect(tester.widget<CustomButton>(cancel).variant, ButtonVariant.tonal);
    expect(tester.widget<CustomButton>(confirm).variant, ButtonVariant.primary);
    final confirmation = tester.widget<AlertDialog>(find.byType(AlertDialog));
    final content = confirmation.content! as Text;
    expect(content.data, isNot(contains('\n')));
    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Wallet details'), findsOneWidget);
    expect(h.device.prompts, 0);
    expect(h.wallet.deletions, isEmpty);
    expect(h.toasts.messages, isEmpty);
    expect(h.wallet.current.activeWallet?.id, _firstId);
  });

  testWidgets('cancelled authentication returns silently without deletion', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => h.dispose(tester));
    h.device.result = DeviceAuthenticationResult.cancelled;
    await h.pump(tester);
    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(h.device.prompts, 1);
    expect(h.wallet.deletions, isEmpty);
    expect(find.text('Wallet details'), findsOneWidget);
    expect(h.toasts.messages, isEmpty);
  });

  for (final lastWallet in [false, true]) {
    testWidgets(
      'successful deletion ${lastWallet ? 'of the last wallet opens Welcome' : 'selects the remaining wallet and opens Home'}',
      (tester) async {
        final h = await _Harness.create(lastWallet: lastWallet);
        addTearDown(() => h.dispose(tester));
        await h.pump(tester);
        await _confirmDeletion(tester);
        await tester.pumpAndSettle();

        expect(h.device.prompts, 1);
        expect(h.device.reasons, ['Delete this wallet']);
        expect(h.wallet.deletions, [_firstId]);
        expect(h.wallet.validAuthorization, isTrue);
        expect(h.wallet.current.wallets, hasLength(lastWallet ? 0 : 1));
        expect(
          h.wallet.current.activeWallet?.id,
          lastWallet ? isNull : _secondId,
        );
        expect(
          find.text(lastWallet ? 'Welcome destination' : 'Home destination'),
          findsOneWidget,
        );
        expect(find.text('Wallet details'), findsNothing);
        expect(h.router!.canPop(), isFalse);
        expect(h.toasts.messages, isEmpty);
      },
    );
  }

  testWidgets('an unsecured device deletes with a scoped grant and no prompt', (
    tester,
  ) async {
    final h = await _Harness.create(secured: false);
    addTearDown(() => h.dispose(tester));
    await h.pump(tester);
    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(h.device.prompts, 0);
    expect(h.wallet.validAuthorization, isTrue);
    expect(h.wallet.deletions, [_firstId]);
    expect(find.text('Home destination'), findsOneWidget);
  });

  testWidgets('rapid taps produce one dialog, one auth, and one delete', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => h.dispose(tester));
    h.device.promptGate = Completer<DeviceAuthenticationResult>();
    h.wallet.deleteGate = Completer<void>();
    await h.pump(tester);
    final delete = _deleteAction;
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.tap(delete, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    final confirm = find.widgetWithText(CustomButton, 'Delete');
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.device.prompts, 1);
    expect(h.wallet.deletions, isEmpty);
    h.device.promptGate!.complete(DeviceAuthenticationResult.authenticated);
    await tester.pump();
    expect(h.wallet.deletions, [_firstId]);
    await tester.tap(_deleteAction, warnIfMissed: false);
    await tester.pump();
    expect(h.device.prompts, 1);
    expect(h.wallet.deletions, [_firstId]);
    h.wallet.deleteGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Home destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing wallets during authentication revokes deletion', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => h.dispose(tester));
    h.device.promptGate = Completer<DeviceAuthenticationResult>();
    await h.pump(tester);
    await _confirmDeletion(tester);
    await tester.pump();
    expect(h.device.prompts, 1);

    h.wallet.publish(h.wallet.current.copyWith(activeWallet: _second));
    h.security.updateWallet(_secondId);
    h.device.promptGate!.complete(DeviceAuthenticationResult.authenticated);
    await tester.pumpAndSettle();

    expect(h.wallet.deletions, isEmpty);
    expect(h.wallet.current.wallets, hasLength(2));
    expect(h.wallet.current.activeWallet?.id, _secondId);
    expect(find.text('Second wallet'), findsOneWidget);
    expect(h.toasts.messages, isEmpty);
  });

  testWidgets('a confirmation cannot delete a newly selected wallet', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => h.dispose(tester));
    await h.pump(tester);
    await _openConfirmation(tester);
    h.wallet.publish(h.wallet.current.copyWith(activeWallet: _second));
    h.security.updateWallet(_secondId);
    await tester.pump();
    await tester.tap(find.widgetWithText(CustomButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(h.device.prompts, 0);
    expect(h.wallet.deletions, isEmpty);
    expect(h.wallet.current.wallets, hasLength(2));
    expect(h.wallet.current.activeWallet?.id, _secondId);
    expect(h.toasts.messages, isEmpty);
  });

  testWidgets(
    'own-auth resume continues before the SecurityGate paints its next frame',
    (tester) async {
      final h = await _Harness.create();
      addTearDown(() => h.dispose(tester));
      h.device.promptGate = Completer<DeviceAuthenticationResult>();
      await h.pump(tester, gated: true);
      await _confirmDeletion(tester);
      await tester.pump(const Duration(milliseconds: 400));
      h.security.handleLifecycle(AppLifecycleState.inactive);
      await tester.pump();
      final route = find
          .byType(WalletDetailsScreen, skipOffstage: false)
          .evaluate()
          .single;
      expect(TickerMode.valuesOf(route).enabled, isFalse);

      h.security.handleLifecycle(AppLifecycleState.resumed);
      h.device.promptGate!.complete(DeviceAuthenticationResult.authenticated);
      for (var turn = 0; turn < 64; turn++) {
        await Future<void>.value();
      }
      expect(h.wallet.deletions, [_firstId]);
      expect(h.device.prompts, 1);
      // Native auth has completed while the inherited widget is still stale.
      expect(TickerMode.valuesOf(route).enabled, isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Home destination'), findsOneWidget);
      expect(h.toasts.messages, isEmpty);
    },
  );

  testWidgets('leaving during authentication prevents a late deletion', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => h.dispose(tester));
    h.device.promptGate = Completer<DeviceAuthenticationResult>();
    await h.pump(tester);
    await _confirmDeletion(tester);
    await tester.pump();
    unawaited(h.router!.push<void>('/other'));
    await tester.pump(const Duration(milliseconds: 400));
    h.device.promptGate!.complete(DeviceAuthenticationResult.authenticated);
    await tester.pumpAndSettle();

    expect(find.text('Other destination'), findsOneWidget);
    expect(h.wallet.deletions, isEmpty);
    expect(h.toasts.messages, isEmpty);
  });

  testWidgets('failed deletion gives one owned toast and no inline message', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => h.dispose(tester));
    h.wallet.failure = _deletionFailure;
    await h.pump(tester);
    await _confirmDeletion(tester);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(h.wallet.deletions, [_firstId]);
    expect(h.wallet.current.wallets, hasLength(2));
    expect(h.wallet.current.activeWallet?.id, _firstId);
    expect(find.text('Wallet details'), findsOneWidget);
    expect(h.toasts.messages, hasLength(1));
    expect(h.toasts.messages.single.message, _deletionFailure.userMessage);
    expect(h.toasts.messages.single.variant, ToastVariant.failure);
    expect(find.text(_deletionFailure.userMessage), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('native authentication failure gives one toast and no deletion', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => h.dispose(tester));
    h.device.error = StateError('Fixture device authentication unavailable');
    await h.pump(tester);
    await _confirmDeletion(tester);
    await tester.pumpAndSettle();

    expect(h.wallet.deletions, isEmpty);
    expect(find.text('Wallet details'), findsOneWidget);
    expect(h.toasts.messages, hasLength(1));
    expect(
      find.textContaining('Device authentication is unavailable'),
      findsNothing,
    );
  });

  testWidgets('an earlier wallet operation failure is not replayed on entry', (
    tester,
  ) async {
    final h = await _Harness.create();
    addTearDown(() => h.dispose(tester));
    h.wallet.initial = h.wallet.initial.copyWith(
      operationFailure: _deletionFailure,
    );
    await h.pump(tester);

    expect(find.text('Wallet details'), findsOneWidget);
    expect(find.text(_deletionFailure.userMessage), findsNothing);
    expect(h.toasts.messages, isEmpty);
  });

  testWidgets('delete confirmation remains usable at narrow large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = await _Harness.create();
    addTearDown(() => h.dispose(tester));
    await h.pump(tester, textScaler: const TextScaler.linear(3));
    final deleteLabel = tester.renderObject<RenderParagraph>(
      find.text('Delete wallet'),
    );
    expect(deleteLabel.didExceedMaxLines, isFalse);
    expect(_deleteAction.hitTestable(), findsOneWidget);
    await _openConfirmation(tester);

    final cancel = find.widgetWithText(CustomButton, 'Cancel');
    final confirm = find.widgetWithText(CustomButton, 'Delete');
    expect(
      tester.getRect(cancel).bottom,
      lessThan(tester.getRect(confirm).top),
    );
    expect(cancel.hitTestable(), findsOneWidget);
    expect(confirm.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(h.device.prompts, 0);
    expect(h.wallet.deletions, isEmpty);
  });

  for (final lateInactive in [false, true]) {
    testWidgets(
      'production app deletes after native auth with ${lateInactive ? 'inactive delayed until final status RPC' : 'reply before Flutter resume'}',
      (tester) async {
        final h = await _NativeHarness.create(
          tester,
          holdFinalStatus: lateInactive,
        );
        addTearDown(() => h.dispose(tester));
        await h.pump(tester);
        expect(find.byType(WalletDetailsScreen), findsOneWidget);
        await _confirmDeletion(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(h.deletePrompts, 1);

        if (lateInactive) {
          // Native and Flutter lifecycle messages use separate channels. The
          // LAContext reply can win the race to Dart, then a delayed inactive
          // event can arrive while the final getStatus RPC is in flight.
          h.deleteReply.complete('authenticated');
          await tester.pump();
          expect(h.finalStatusHeld, isTrue);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          h.finalStatusGate.complete();
          await tester.pump();
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          h.deleteReply.complete('authenticated');
          await tester.pump();
          expect(h.security.isAuthenticating, isTrue);
        }

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        final registry = await h.profiles.read();
        expect(
          (registry as AppSuccess<WalletRegistry>).value.profiles,
          isEmpty,
        );
        expect(find.byType(OnboardingWelcomeScreen), findsOneWidget);
        expect(find.byType(WalletDetailsScreen), findsNothing);
        expect(h.deletePrompts, 1);
        expect(h.security.isLocked, isFalse);
        expect(h.container.read(toastControllerProvider).current, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a genuine native background during final status revokes deletion',
    (tester) async {
      final h = await _NativeHarness.create(tester, holdFinalStatus: true);
      addTearDown(() => h.dispose(tester));
      await h.pump(tester);
      await _confirmDeletion(tester);
      h.deleteReply.complete('authenticated');
      await tester.pump();
      expect(h.finalStatusHeld, isTrue);
      await h.sendNativeEvent(tester, const MethodCall('backgrounded'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      h.finalStatusGate.complete();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      final registry = await h.profiles.read();
      expect(
        (registry as AppSuccess<WalletRegistry>).value.profiles.single.id,
        _firstId,
      );
      expect(
        h.container.read(walletViewModelProvider).value?.activeWallet?.id,
        _firstId,
      );
      expect(find.byType(WalletDetailsScreen), findsOneWidget);
      expect(h.deletePrompts, 1);
      expect(h.container.read(toastControllerProvider).current, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a committed wallet switch during final native status revokes deletion',
    (tester) async {
      final h = await _NativeHarness.create(
        tester,
        holdFinalStatus: true,
        includeSecondWallet: true,
      );
      addTearDown(() => h.dispose(tester));
      await h.pump(tester);
      await _confirmDeletion(tester);
      h.deleteReply.complete('authenticated');
      await tester.pump();
      expect(h.finalStatusHeld, isTrue);
      final switched = h.container
          .read(walletViewModelProvider.notifier)
          .switchWallet(_secondId);
      await tester.pump();
      expect(await switched, isTrue);
      h.finalStatusGate.complete();
      await tester.pumpAndSettle();

      final registry = await h.profiles.read();
      final snapshot = (registry as AppSuccess<WalletRegistry>).value;
      expect(snapshot.profiles, hasLength(2));
      expect(snapshot.activeWalletId, _secondId);
      expect(find.byType(WalletDetailsScreen), findsOneWidget);
      expect(find.text('Second wallet'), findsOneWidget);
      expect(h.deletePrompts, 1);
      expect(h.container.read(toastControllerProvider).current, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder get _deleteAction => find.widgetWithText(CustomButton, 'Delete wallet');

Future<void> _openConfirmation(WidgetTester tester) async {
  await tester.ensureVisible(_deleteAction);
  await tester.tap(_deleteAction);
  await tester.pumpAndSettle();
  expect(find.text('Delete wallet?'), findsOneWidget);
}

Future<void> _confirmDeletion(WidgetTester tester) async {
  await _openConfirmation(tester);
  await tester.tap(find.widgetWithText(CustomButton, 'Delete'));
  await tester.pump();
}

const _firstId = '11111111111111111111111111111111';
const _secondId = '22222222222222222222222222222222';
final _first = _profile(_firstId, 'First wallet');
final _second = _profile(_secondId, 'Second wallet');
const _deletionFailure = AppFailure(
  code: 'wallet_fixture_delete_failed',
  kind: AppFailureKind.storage,
  userMessage: 'The wallet could not be removed. Try again.',
  retryable: true,
);

WalletProfile _profile(String id, String name) => WalletProfile(
  id: id,
  name: name,
  createdAt: DateTime.utc(2026, 10, 26),
  updatedAt: DateTime.utc(2026, 10, 26),
  environment: BlockchainEnvironment.regtest,
  state: WalletProfileState.ready,
  storageToken: id,
);

final class _Device implements DeviceAuthentication {
  _Device(this.securityStatus);
  final DeviceSecurityStatus securityStatus;
  DeviceAuthenticationResult result = DeviceAuthenticationResult.authenticated;
  Completer<DeviceAuthenticationResult>? promptGate;
  Object? error;
  int prompts = 0;
  final reasons = <String>[];

  @override
  bool get isCaptured => false;
  @override
  Stream<bool> get captureChanges => const Stream.empty();
  @override
  Future<DeviceSecurityStatus> status() async => securityStatus;
  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) async {
    prompts++;
    reasons.add(reason);
    if (error != null) throw error!;
    return promptGate == null ? result : promptGate!.future;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> setSensitive(bool value) async {}
}

final class _Wallet extends WalletViewModel {
  _Wallet(this.initial, this.security);
  WalletState initial;
  final SecurityController security;
  final deletions = <String>[];
  bool validAuthorization = false;
  AppFailure? failure;
  Completer<void>? deleteGate;

  WalletState get current => state.requireValue;

  @override
  Future<WalletState> build() async => initial;

  void publish(WalletState next) => state = AsyncData(next);

  @override
  Future<bool> deleteWallet(
    String walletId, {
    SensitiveAuthorization? authorization,
  }) async {
    deletions.add(walletId);
    validAuthorization = security.consume(
      authorization,
      SecurityPurpose.deleteWallet,
      walletId: walletId,
    );
    if (!validAuthorization) return false;
    final before = current;
    state = AsyncData(
      before.copyWith(deletingWalletId: walletId, operationFailure: null),
    );
    await deleteGate?.future;
    if (failure != null) {
      state = AsyncData(before.copyWith(operationFailure: failure));
      return false;
    }
    final remaining = before.wallets.where((p) => p.id != walletId).toList();
    final next = remaining.isEmpty ? null : remaining.first;
    state = AsyncData(WalletState(wallets: remaining, activeWallet: next));
    if (next == null) {
      security.clearWalletPresence();
    } else {
      security.updateWallet(next.id);
    }
    return true;
  }
}

final class _Harness {
  late final _Device device;
  late final SecurityController security;
  late final _Wallet wallet;
  final toasts = RecordingToastPresentationService();
  final haptics = RecordingHapticFeedbackService();
  ProviderContainer? container;
  GoRouter? router;

  static Future<_Harness> create({
    bool lastWallet = false,
    bool secured = true,
  }) async {
    final h = _Harness();
    h.device = _Device(
      secured ? DeviceSecurityStatus.secured : DeviceSecurityStatus.unsecured,
    );
    h.security = SecurityController(h.device);
    await h.security.initialize(hasWallet: true);
    h.security.updateWallet(_firstId);
    if (h.security.isLocked) await h.security.unlock();
    h.device.prompts = 0;
    h.device.reasons.clear();
    h.wallet = _Wallet(
      WalletState(
        wallets: [_first, if (!lastWallet) _second],
        activeWallet: _first,
      ),
      h.security,
    );
    return h;
  }

  Future<void> pump(
    WidgetTester tester, {
    TextScaler textScaler = TextScaler.noScaling,
    bool gated = false,
  }) async {
    container = ProviderContainer(
      overrides: [
        securityControllerProvider.overrideWithValue(security),
        walletViewModelProvider.overrideWith(() => wallet),
      ],
    );
    router = GoRouter(
      initialLocation: '/details',
      routes: [
        GoRoute(
          path: '/details',
          builder: (_, _) => const WalletDetailsScreen(),
        ),
        GoRoute(
          path: RoutePaths.home,
          name: RouteNames.home,
          builder: (_, _) => const Scaffold(body: Text('Home destination')),
        ),
        GoRoute(
          path: RoutePaths.onboardingWelcome,
          name: RouteNames.onboardingWelcome,
          builder: (_, _) => const Scaffold(body: Text('Welcome destination')),
        ),
        GoRoute(
          path: '/other',
          builder: (_, _) => const Scaffold(body: Text('Other destination')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container!,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router!,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: AsterFeedbackScope(
              haptics: haptics,
              toasts: toasts,
              child: gated
                  ? SecurityGate(controller: security, child: child!)
                  : child!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    router?.dispose();
    container?.dispose();
    security.dispose();
  }
}

/// Uses the actual app composition, router, repository and platform adapter.
/// Only the OS transport and wallet storage/engine boundaries are in memory.
final class _NativeHarness {
  static const channel = MethodChannel('aster.test.delete_native_order');
  final deleteReply = Completer<String>();
  final finalStatusGate = Completer<void>();
  bool finalStatusHeld = false;
  bool _deleteReplied = false;
  int deletePrompts = 0;
  late final SecurityController security;
  late final WalletProfileStore profiles;
  late final WalletRepository repository;
  late final ProviderContainer container;
  ProviderSubscription<GoRouter>? _routerLease;

  static Future<_NativeHarness> create(
    WidgetTester tester, {
    required bool holdFinalStatus,
    bool includeSecondWallet = false,
  }) async {
    final h = _NativeHarness();
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
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(List.generate(10, (_) => FakeWalletEngine())),
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
      ],
    );
    await bootstrapApplicationContainer(h.container);
    h._routerLease = h.container.listen(appRouterProvider, (_, _) {});
    h.container.read(appRouterProvider).goNamed(RouteNames.walletDetails);
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

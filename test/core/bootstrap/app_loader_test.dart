import 'dart:async';

import 'package:aster/core/bootstrap/app_loader.dart';
import 'package:aster/core/errors/errors.dart';
import 'package:aster/core/security/device_authentication.dart';
import 'package:aster/core/security/security_controller.dart';
import 'package:aster/core/security/security_gate.dart';
import 'package:aster/shared/screens/screens.dart';
import 'package:aster/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('real launch ordering never paints manual unlock controls before '
      'or during the automatic prompt', (tester) async {
    final device = _LoaderDevice();
    final security = SecurityController(device);
    addTearDown(security.dispose);
    final initialStatus = device.nextStatus();
    final initialPrompt = device.nextPrompt();
    var observing = true;
    final paintedFrames = <({bool controls, int prompts})>[];
    void recordFrame(Duration _) {
      if (!observing) return;
      paintedFrames.add((
        controls:
            find.text('Aster locked').evaluate().isNotEmpty ||
            find.text('Unlock').evaluate().isNotEmpty,
        prompts: device.prompts,
      ));
      tester.binding.addPostFrameCallback(recordFrame);
    }

    tester.binding.addPostFrameCallback(recordFrame);
    addTearDown(() => observing = false);
    var walletOpenCount = 0;
    await tester.pumpWidget(
      AppLoader(
        security: security,
        initialize: () async {
          // Match main.dart, including its deliberately painted Flutter frame
          // between capability discovery and the automatic OS prompt.
          await security.initialize(hasWallet: true);
          await WidgetsBinding.instance.endOfFrame;
          await security.waitForUnlock();
          walletOpenCount += 1;
          return ProviderContainer();
        },
        child: const MaterialApp(home: Text('Authenticated wallet')),
      ),
    );
    expect(find.text('Aster locked'), findsNothing);
    expect(find.text('Unlock'), findsNothing);
    initialStatus.complete(DeviceSecurityStatus.secured);
    for (var frame = 0; frame < 4; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Aster locked'), findsNothing);
      expect(find.text('Unlock'), findsNothing);
      expect(find.text('Authenticated wallet'), findsNothing);
      expect(find.byType(AnimatedSplashScreen), findsNothing);
    }
    expect(paintedFrames.where((frame) => frame.prompts == 0), isNotEmpty);
    expect(
      paintedFrames.every((frame) => !frame.controls),
      isTrue,
      reason: 'A single premature frame would flash controls before Face ID.',
    );
    expect(device.prompts, 1);
    expect(walletOpenCount, 0);

    initialPrompt.complete(DeviceAuthenticationResult.cancelled);
    await tester.pump();
    await tester.pump();
    expect(find.text('Aster locked'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(walletOpenCount, 0);
    final retry = device.nextPrompt();
    final retryFrameStart = paintedFrames.length;
    await tester.tap(find.text('Unlock'));
    for (var frame = 0; frame < 3; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Aster locked'), findsNothing);
      expect(find.text('Unlock'), findsNothing);
      expect(walletOpenCount, 0);
    }
    expect(
      paintedFrames.skip(retryFrameStart).every((frame) => !frame.controls),
      isTrue,
    );
    expect(device.prompts, 2);
    retry.complete(DeviceAuthenticationResult.authenticated);
    await tester.pump();
    await tester.pump();
    expect(walletOpenCount, 1);
    final reveal = tester
        .widget<AnimatedSplashScreen>(find.byType(AnimatedSplashScreen))
        .controller;
    expect(reveal.value, 0);
    await tester.pump(const AsterMotion().bootstrapRevealDelay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(reveal.value, greaterThan(0));
    await tester.pumpAndSettle(const AsterMotion().splashRevealDuration);
    expect(find.bySemanticsLabel('Authenticated wallet'), findsOneWidget);
  });

  testWidgets('automatic foreground authentication stays quiet until cancel; '
      'Lock now deliberately offers Unlock', (tester) async {
    final device = _LoaderDevice();
    final security = SecurityController(device);
    addTearDown(security.dispose);
    await security.initialize(hasWallet: false);
    security.updateWallet('wallet-a');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SecurityGate(
          controller: security,
          child: const Text('Wallet settings'),
        ),
      ),
    );
    security.handleLifecycle(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Wallet settings'), findsNothing);
    expect(find.text('Aster locked'), findsNothing);
    expect(find.text('Unlock'), findsNothing);
    final status = device.nextStatus();
    final prompt = device.nextPrompt();
    security.handleLifecycle(AppLifecycleState.resumed);
    final preparing = security.prepareForeground();
    await tester.pump();
    expect(find.text('Aster locked'), findsNothing);
    expect(find.text('Unlock'), findsNothing);
    status.complete(DeviceSecurityStatus.secured);
    for (var frame = 0; frame < 3; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Aster locked'), findsNothing);
      expect(find.text('Unlock'), findsNothing);
      expect(find.text('Wallet settings'), findsNothing);
    }
    expect(device.prompts, 1);
    prompt.complete(DeviceAuthenticationResult.cancelled);
    expect(await preparing, isFalse);
    await tester.pump();
    expect(find.text('Aster locked'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    final retry = device.nextPrompt();
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(find.text('Aster locked'), findsNothing);
    expect(find.text('Unlock'), findsNothing);
    retry.complete(DeviceAuthenticationResult.authenticated);
    await tester.pump();
    await tester.pump();
    expect(find.text('Wallet settings'), findsOneWidget);

    security.lock();
    await tester.pump();
    expect(find.text('Aster locked'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.text('Wallet settings'), findsNothing);
  });

  testWidgets('cancelled cold launch retains a usable manual unlock after '
      'background and resume before the app container is mounted', (
    tester,
  ) async {
    final device = _LoaderDevice();
    final security = SecurityController(device);
    addTearDown(security.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final first = device.nextPrompt();
    var walletOpenCount = 0;
    await tester.pumpWidget(
      AppLoader(
        security: security,
        initialize: () async {
          await security.initialize(hasWallet: true);
          await WidgetsBinding.instance.endOfFrame;
          await security.waitForUnlock();
          walletOpenCount += 1;
          return ProviderContainer();
        },
        child: const MaterialApp(home: Text('Authenticated wallet')),
      ),
    );
    await _pumpForPrompt(tester, device, 1);
    first.complete(DeviceAuthenticationResult.cancelled);
    await tester.pump();
    await tester.pump();
    expect(find.text('Unlock'), findsOneWidget);
    expect(walletOpenCount, 0);

    device.background();
    _background(tester);
    await tester.pump();
    final resumed = device.nextPrompt();
    _foreground(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('Aster locked'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(device.prompts, 1);
    await tester.tap(find.text('Unlock'));
    await _pumpForPrompt(tester, device, 2);
    expect(find.text('Aster locked'), findsNothing);
    expect(find.text('Unlock'), findsNothing);
    expect(find.text('Authenticated wallet'), findsNothing);
    expect(walletOpenCount, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(device.prompts, 2, reason: 'Startup must have one prompt owner.');

    resumed.complete(DeviceAuthenticationResult.authenticated);
    await tester.pump();
    await tester.pump();
    expect(walletOpenCount, 1);
    expect(
      tester
          .widget<AnimatedSplashScreen>(find.byType(AnimatedSplashScreen))
          .controller
          .value,
      0,
    );
    await tester.pump(const AsterMotion().bootstrapRevealDelay);
    await tester.pump();
    await tester.pumpAndSettle(const AsterMotion().splashRevealDuration);
    expect(find.bySemanticsLabel('Authenticated wallet'), findsOneWidget);
    expect(device.prompts, 2);
  });

  testWidgets('background during bootstrap retains a manual unlock action '
      'and does not reveal until authentication succeeds', (tester) async {
    final device = _LoaderDevice();
    final security = SecurityController(device);
    addTearDown(security.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final bootstrap = Completer<ProviderContainer>();
    final first = device.nextPrompt();
    var bootstrapsStarted = 0;
    await tester.pumpWidget(
      AppLoader(
        security: security,
        initialize: () async {
          await security.initialize(hasWallet: true);
          await WidgetsBinding.instance.endOfFrame;
          await security.waitForUnlock();
          bootstrapsStarted += 1;
          return bootstrap.future;
        },
        child: const MaterialApp(home: Text('Bootstrapped wallet')),
      ),
    );
    await _pumpForPrompt(tester, device, 1);
    first.complete(DeviceAuthenticationResult.authenticated);
    await tester.pump();
    expect(bootstrapsStarted, 1);
    device.background();
    _background(tester);
    await tester.pump();
    final resumed = device.nextPrompt();
    _foreground(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('Unlock'), findsOneWidget);
    expect(device.prompts, 1);
    bootstrap.complete(ProviderContainer());
    await tester.pump();
    await tester.pump();
    expect(find.byType(AnimatedSplashScreen), findsNothing);
    expect(find.text('Unlock'), findsOneWidget);
    await tester.tap(find.text('Unlock'));
    await _pumpForPrompt(tester, device, 2);
    expect(find.text('Unlock'), findsNothing);
    expect(bootstrapsStarted, 1);
    expect(device.prompts, 2);

    resumed.complete(DeviceAuthenticationResult.authenticated);
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<AnimatedSplashScreen>(find.byType(AnimatedSplashScreen))
          .controller
          .value,
      0,
    );
    await tester.pump(const AsterMotion().bootstrapRevealDelay);
    await tester.pump();
    await tester.pumpAndSettle(const AsterMotion().splashRevealDuration);
    expect(find.bySemanticsLabel('Bootstrapped wallet'), findsOneWidget);
    expect(bootstrapsStarted, 1);
    expect(device.prompts, 2);
  });

  testWidgets('authentication holds bootstrap and preserves the full reveal', (
    tester,
  ) async {
    final device = _LoaderDevice();
    final security = SecurityController(device);
    addTearDown(security.dispose);
    await security.initialize(hasWallet: true);
    final prompt = device.nextPrompt();
    var walletOpenCount = 0;
    await tester.pumpWidget(
      AppLoader(
        security: security,
        initialize: () async {
          await security.waitForUnlock();
          walletOpenCount += 1;
          return ProviderContainer();
        },
        child: const MaterialApp(home: Text('Authenticated wallet')),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(device.prompts, 1);
    expect(walletOpenCount, 0);
    expect(find.byType(AnimatedSplashScreen), findsNothing);
    expect(find.text('Authenticated wallet'), findsNothing);
    expect(find.text('Unlock'), findsNothing);

    prompt.complete(DeviceAuthenticationResult.authenticated);
    await tester.pump();
    await tester.pump();
    expect(walletOpenCount, 1);
    final animation = tester
        .widget<AnimatedSplashScreen>(find.byType(AnimatedSplashScreen))
        .controller;
    expect(animation.value, 0);
    expect(find.bySemanticsLabel('Authenticated wallet'), findsNothing);
    const motion = AsterMotion();
    await tester.pump(motion.bootstrapRevealDelay);
    await tester.pump();
    expect(animation.value, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(animation.value, greaterThan(0));
    expect(animation.value, lessThan(1));
    await tester.pumpAndSettle(motion.splashRevealDuration);
    expect(find.bySemanticsLabel('Authenticated wallet'), findsOneWidget);
    expect(device.prompts, 1);
  });

  testWidgets(
    'cancelled launch stays locked until the Unlock button is tapped',
    (tester) async {
      final device = _LoaderDevice()
        ..outcome = DeviceAuthenticationResult.cancelled;
      final security = SecurityController(device);
      addTearDown(security.dispose);
      await security.initialize(hasWallet: true);
      var walletOpenCount = 0;
      await tester.pumpWidget(
        AppLoader(
          security: security,
          initialize: () async {
            await security.waitForUnlock();
            walletOpenCount += 1;
            return ProviderContainer();
          },
          child: const MaterialApp(home: Text('Authenticated wallet')),
        ),
      );
      await tester.pump();
      expect(find.text('Aster locked'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
      expect(walletOpenCount, 0);
      expect(device.prompts, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(device.prompts, 1);

      device.outcome = DeviceAuthenticationResult.authenticated;
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const AsterMotion().bootstrapRevealDelay);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(walletOpenCount, 1);
      expect(device.prompts, 2);
      expect(find.bySemanticsLabel('Authenticated wallet'), findsOneWidget);
    },
  );

  testWidgets(
    'background during reveal restarts it after auth; warm unlock does not replay',
    (tester) async {
      final device = _LoaderDevice();
      final security = SecurityController(device);
      addTearDown(security.dispose);
      await security.initialize(hasWallet: false);
      security.updateWallet('wallet-a');
      await tester.pumpWidget(
        AppLoader(
          security: security,
          initialize: () async => ProviderContainer(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: SecurityGate(
              controller: security,
              child: const Text('Wallet settings'),
            ),
          ),
        ),
      );
      await tester.pump();
      const motion = AsterMotion();
      await tester.pump(motion.bootstrapRevealDelay);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<AnimatedSplashScreen>(find.byType(AnimatedSplashScreen))
            .controller
            .value,
        greaterThan(0),
      );
      security.handleLifecycle(AppLifecycleState.paused);
      await tester.pump();
      expect(find.byType(AnimatedSplashScreen), findsNothing);
      expect(find.bySemanticsLabel('Wallet settings'), findsNothing);
      security.handleLifecycle(AppLifecycleState.resumed);
      expect(await security.unlock(), isTrue);
      await tester.pump();
      final restarted = tester
          .widget<AnimatedSplashScreen>(find.byType(AnimatedSplashScreen))
          .controller;
      expect(restarted.value, 0);
      await tester.pump(motion.bootstrapRevealDelay);
      await tester.pump();
      await tester.pumpAndSettle(motion.splashRevealDuration);
      expect(find.bySemanticsLabel('Wallet settings'), findsOneWidget);

      security.handleLifecycle(AppLifecycleState.paused);
      await tester.pump();
      expect(find.bySemanticsLabel('Wallet settings'), findsNothing);
      security.handleLifecycle(AppLifecycleState.resumed);
      expect(await security.unlock(), isTrue);
      await tester.pump();
      expect(find.byType(AnimatedSplashScreen), findsNothing);
      expect(find.bySemanticsLabel('Wallet settings'), findsOneWidget);
    },
  );

  testWidgets('unsecured first launch reveals normally without a prompt', (
    tester,
  ) async {
    final device = _LoaderDevice()..secured = false;
    final security = SecurityController(device);
    addTearDown(security.dispose);
    await security.initialize(hasWallet: false);
    await tester.pumpWidget(
      AppLoader(
        security: security,
        initialize: () async {
          await security.waitForUnlock();
          return ProviderContainer();
        },
        child: const MaterialApp(home: Text('Welcome')),
      ),
    );
    await tester.pump();
    await tester.pump(const AsterMotion().bootstrapRevealDelay);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Welcome'), findsOneWidget);
    expect(device.prompts, 0);
  });

  testWidgets('startup splash owns semantics until the app is revealed', (
    tester,
  ) async {
    final initialization = Completer<ProviderContainer>();
    await tester.pumpWidget(
      AppLoader(
        initialize: () => initialization.future,
        child: const MaterialApp(home: Text('Ready')),
      ),
    );

    expect(find.bySemanticsLabel('Opening Aster'), findsOneWidget);
    expect(find.bySemanticsLabel('Ready'), findsNothing);

    initialization.complete(ProviderContainer());
    await tester.pump();
    await tester.pump();

    expect(find.text('Ready'), findsOneWidget);
    expect(find.bySemanticsLabel('Opening Aster'), findsOneWidget);
    expect(find.bySemanticsLabel('Ready'), findsNothing);

    const motion = AsterMotion();
    await tester.pump(motion.bootstrapRevealDelay);
    await tester.pump();
    await tester.pumpAndSettle(motion.splashRevealDuration);
    expect(find.bySemanticsLabel('Opening Aster'), findsNothing);
    expect(find.bySemanticsLabel('Ready'), findsOneWidget);
  });

  testWidgets('shows redacted bootstrap failure and can recover on retry', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      AppLoader(
        initialize: () async {
          attempts += 1;
          if (attempts == 1) {
            throw const AppFailureException(
              AppFailure(
                code: 'test_bootstrap_failure',
                kind: AppFailureKind.storage,
                userMessage: 'Wallet data could not be opened safely.',
                retryable: true,
              ),
            );
          }
          return ProviderContainer();
        },
        child: const MaterialApp(home: Text('Ready')),
      ),
    );
    await tester.pump();

    expect(find.text('Wallet could not be opened'), findsOneWidget);
    expect(
      find.text('Wallet data could not be opened safely.'),
      findsOneWidget,
    );
    final failure = find.bySemanticsLabel(
      'Wallet data could not be opened safely.',
    );
    expect(failure, findsOneWidget);
    expect(tester.getSemantics(failure).flagsCollection.isLiveRegion, isTrue);
    final failureContext = tester.element(
      find.text('Wallet could not be opened'),
    );
    final surface = Theme.of(failureContext).colorScheme.surface;
    final systemStyles = tester
        .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        )
        .map((region) => region.value);
    expect(
      systemStyles,
      contains(
        isA<SystemUiOverlayStyle>()
            .having(
              (style) => style.systemNavigationBarColor,
              'navigation bar color',
              surface,
            )
            .having(
              (style) => style.systemNavigationBarIconBrightness,
              'navigation icon brightness',
              Brightness.dark,
            )
            .having(
              (style) => style.statusBarIconBrightness,
              'status icon brightness',
              Brightness.dark,
            ),
      ),
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Wallet could not be opened'), findsNothing);
  });

  testWidgets('does not offer retry when startup outcome is unknown', (
    tester,
  ) async {
    await tester.pumpWidget(
      AppLoader(
        initialize: () async {
          throw const AppFailureException(
            AppFailure(
              code: 'test_bootstrap_outcome_unknown',
              kind: AppFailureKind.storage,
              userMessage: 'Restart the app before continuing.',
              retryable: false,
              outcomeUnknown: true,
            ),
          );
        },
        child: const MaterialApp(home: Text('Ready')),
      ),
    );
    await tester.pump();

    expect(find.text('Restart the app before continuing.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}

final class _LoaderDevice
    implements DeviceAuthentication, DeviceAuthenticationBackgroundEvents {
  _LoaderDevice() {
    addTearDown(_backgroundEvents.close);
  }
  bool secured = true;
  int prompts = 0;
  DeviceAuthenticationResult outcome = DeviceAuthenticationResult.authenticated;
  Completer<DeviceAuthenticationResult>? _prompt;
  Completer<DeviceSecurityStatus>? _status;
  final _backgroundEvents = StreamController<void>.broadcast(sync: true);

  Completer<DeviceAuthenticationResult> nextPrompt() =>
      _prompt = Completer<DeviceAuthenticationResult>();

  Completer<DeviceSecurityStatus> nextStatus() =>
      _status = Completer<DeviceSecurityStatus>();

  @override
  Future<DeviceSecurityStatus> status() async {
    final pending = _status;
    _status = null;
    return pending == null
        ? secured
              ? DeviceSecurityStatus.secured
              : DeviceSecurityStatus.unsecured
        : await pending.future;
  }

  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) async {
    prompts += 1;
    final pending = _prompt;
    _prompt = null;
    return pending == null ? outcome : await pending.future;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> setSensitive(bool sensitive) async {}

  @override
  Stream<bool> get captureChanges => const Stream<bool>.empty();

  @override
  bool get isCaptured => false;

  @override
  Stream<void> get backgroundEvents => _backgroundEvents.stream;

  void background() => _backgroundEvents.add(null);
}

Future<void> _pumpForPrompt(
  WidgetTester tester,
  _LoaderDevice device,
  int count,
) async {
  for (var frame = 0; frame < 20 && device.prompts < count; frame += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(device.prompts, count);
  // tester.tap can enter authenticate in its microtasks before the frame that
  // removes manual controls has painted. Observe the presented prompt frame.
  await tester.pump();
}

void _background(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void _foreground(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

import 'dart:async';

import 'package:aster/core/bootstrap/app_loader.dart';
import 'package:aster/core/errors/errors.dart';
import 'package:aster/core/security/device_authentication.dart';
import 'package:aster/core/security/security_controller.dart';
import 'package:aster/core/security/security_gate.dart';
import 'package:aster/shared/screens/screens.dart';
import 'package:aster/shared/theme/theme.dart';
import 'package:aster/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launch holds the initial artwork, then completes colour before '
      'starting the original reveal', (tester) async {
    final bootstrap = Completer<ProviderContainer>();
    await tester.pumpWidget(
      AppLoader(
        initialize: () => bootstrap.future,
        child: const MaterialApp(
          home: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: Text('Ready'),
          ),
        ),
      ),
    );
    final splash = tester.widget<AnimatedSplashScreen>(_runningSplash);
    expect(splash.colorTransition.value, 0);
    expect(splash.controller.value, 0);
    void expectDarkStartupBars() {
      final style = _launchSystemStyle(tester);
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.statusBarBrightness, Brightness.light);
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    }

    expectDarkStartupBars();
    await tester.pump(const Duration(seconds: 5));
    expect(splash.colorTransition.value, 0);
    expect(splash.controller.value, 0);

    bootstrap.complete(ProviderContainer());
    await tester.pump();
    await tester.pump();
    const motion = AsterMotion();
    await tester.pump(motion.bootstrapRevealDelay);
    await tester.pump();
    await tester.pump(motion.splashColorTransitionDuration ~/ 2);
    expect(splash.colorTransition.value, closeTo(0.5, 0.0001));
    expect(splash.controller.value, 0);
    expectDarkStartupBars();
    expect(find.bySemanticsLabel('Ready'), findsNothing);
    await tester.pump(motion.splashColorTransitionDuration ~/ 2);
    expect(splash.colorTransition.value, 1);
    expect(splash.controller.value, 0);
    expectDarkStartupBars();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    expect(splash.controller.value, closeTo(0.1, 0.0001));
    expectDarkStartupBars();
    await tester.pumpAndSettle();
    expect(_runningSplash, findsNothing);
    expect(find.bySemanticsLabel('Ready'), findsOneWidget);
    expect(_launchSystemStyle(tester), SystemUiOverlayStyle.light);
  });

  testWidgets('background during colour transition cancels both phases and '
      'restarts from the initial artwork after authentication', (tester) async {
    final device = _LoaderDevice();
    final security = SecurityController(device);
    addTearDown(security.dispose);
    await security.initialize(hasWallet: false);
    security.updateWallet('wallet-a');
    await tester.pumpWidget(
      AppLoader(
        security: security,
        initialize: () async => ProviderContainer(),
        child: const MaterialApp(home: Text('Ready')),
      ),
    );
    await tester.pump();
    const motion = AsterMotion();
    await tester.pump(motion.bootstrapRevealDelay);
    await tester.pump();
    await tester.pump(motion.splashColorTransitionDuration ~/ 2);
    final before = tester.widget<AnimatedSplashScreen>(_runningSplash);
    expect(before.colorTransition.value, greaterThan(0));
    expect(before.controller.value, 0);
    security.handleLifecycle(AppLifecycleState.paused);
    await tester.pump();
    expect(_runningSplash, findsNothing);
    expect(before.colorTransition.value, 0);
    expect(before.controller.value, 0);
    final held = tester.widget<AnimatedSplashScreen>(
      find.descendant(
        of: find.byType(AsterLockScreen),
        matching: find.byType(AnimatedSplashScreen),
      ),
    );
    expect(held.controller.value, 0);
    expect(held.colorTransition.value, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(before.colorTransition.value, 0);
    expect(before.controller.value, 0);
    expect(find.bySemanticsLabel('Ready'), findsNothing);

    security.handleLifecycle(AppLifecycleState.resumed);
    expect(await security.unlock(), isTrue);
    await tester.pump();
    final resumed = tester.widget<AnimatedSplashScreen>(_runningSplash);
    expect(resumed.colorTransition.value, 0);
    expect(resumed.controller.value, 0);
    await tester.pump(motion.bootstrapRevealDelay);
    await tester.pump();
    await tester.pump(motion.splashColorTransitionDuration);
    expect(resumed.colorTransition.value, 1);
    expect(resumed.controller.value, 0);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Ready'), findsOneWidget);
  });

  testWidgets('repeated security updates do not restart the colour phase', (
    tester,
  ) async {
    final security = SecurityController(_LoaderDevice());
    addTearDown(security.dispose);
    await security.initialize(hasWallet: false);
    await tester.pumpWidget(
      AppLoader(
        security: security,
        initialize: () async => ProviderContainer(),
        child: const MaterialApp(home: Text('Ready')),
      ),
    );
    await tester.pump();
    const motion = AsterMotion();
    await tester.pump(motion.bootstrapRevealDelay);
    await tester.pump();
    await tester.pump(motion.splashColorTransitionDuration ~/ 2);
    final splash = tester.widget<AnimatedSplashScreen>(_runningSplash);
    await security.refreshStatus();
    await tester.pump(motion.splashColorTransitionDuration ~/ 2);
    expect(splash.colorTransition.value, 1);
    expect(splash.controller.value, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    expect(splash.controller.value, closeTo(0.1, 0.0001));
    await tester.pumpAndSettle();
  });

  testWidgets('reduced motion skips the delay and both decorative phases', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: AppLoader(
          initialize: () async => ProviderContainer(),
          child: const MaterialApp(home: Text('Ready')),
        ),
      ),
    );
    final splash = tester.widget<AnimatedSplashScreen>(_runningSplash);
    await tester.pump();
    await tester.pump();
    expect(splash.colorTransition.value, 1);
    expect(splash.controller.value, 1);
    expect(_runningSplash, findsNothing);
    expect(find.bySemanticsLabel('Ready'), findsOneWidget);
  });

  testWidgets('disposing during the colour phase cancels pending reveal work', (
    tester,
  ) async {
    await tester.pumpWidget(
      AppLoader(
        initialize: () async => ProviderContainer(),
        child: const MaterialApp(home: Text('Ready')),
      ),
    );
    await tester.pump();
    await tester.pump(const AsterMotion().bootstrapRevealDelay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final splash = tester.widget<AnimatedSplashScreen>(_runningSplash);
    expect(splash.colorTransition.value, greaterThan(0));
    expect(splash.controller.value, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold and warm lock hold the same initial appearance without '
      'replaying startup after a warm unlock', (tester) async {
    final device = _LoaderDevice();
    final security = SecurityController(device);
    addTearDown(security.dispose);
    await security.initialize(hasWallet: true);
    final prompt = device.nextPrompt();
    await tester.pumpWidget(
      AppLoader(
        security: security,
        initialize: () async {
          await security.waitForUnlock();
          return ProviderContainer();
        },
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SecurityGate(controller: security, child: const Text('Ready')),
        ),
      ),
    );
    expect(security.canAccessWallet, isFalse);
    expect(find.text('Ready'), findsNothing);
    AnimatedSplashScreen heldCover() => tester.widget<AnimatedSplashScreen>(
      find.descendant(
        of: find.byType(AsterLockScreen),
        matching: find.byType(AnimatedSplashScreen),
      ),
    );
    expect(heldCover().controller.value, 0);
    expect(heldCover().colorTransition.value, 0);
    prompt.complete(DeviceAuthenticationResult.authenticated);
    await tester.pump();
    await tester.pump();
    await tester.pump(const AsterMotion().bootstrapRevealDelay);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Ready'), findsOneWidget);
    expect(security.canAccessWallet, isTrue);
    security.lock();
    await tester.pump();
    expect(find.bySemanticsLabel('Ready'), findsNothing);
    expect(heldCover().controller.value, 0);
    expect(heldCover().colorTransition.value, 0);
    expect(_runningSplash, findsNothing);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Ready'), findsOneWidget);
    expect(_runningSplash, findsNothing);
    expect(tester.takeException(), isNull);
  });

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
      expect(_runningSplash, findsNothing);
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
        .widget<AnimatedSplashScreen>(_runningSplash)
        .controller;
    expect(reveal.value, 0);
    await tester.pump(const AsterMotion().bootstrapRevealDelay);
    await tester.pump();
    await tester.pump(const AsterMotion().splashColorTransitionDuration);
    await tester.pump(const Duration(milliseconds: 1));
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
      tester.widget<AnimatedSplashScreen>(_runningSplash).controller.value,
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
    expect(_runningSplash, findsNothing);
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
      tester.widget<AnimatedSplashScreen>(_runningSplash).controller.value,
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
    expect(_runningSplash, findsNothing);
    expect(find.text('Authenticated wallet'), findsNothing);
    expect(find.text('Unlock'), findsNothing);

    prompt.complete(DeviceAuthenticationResult.authenticated);
    await tester.pump();
    await tester.pump();
    expect(walletOpenCount, 1);
    final animation = tester
        .widget<AnimatedSplashScreen>(_runningSplash)
        .controller;
    expect(animation.value, 0);
    expect(find.bySemanticsLabel('Authenticated wallet'), findsNothing);
    const motion = AsterMotion();
    await tester.pump(motion.bootstrapRevealDelay);
    await tester.pump();
    expect(animation.value, 0);
    await tester.pump(motion.splashColorTransitionDuration);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
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
      await tester.pump(motion.splashColorTransitionDuration);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<AnimatedSplashScreen>(_runningSplash).controller.value,
        greaterThan(0),
      );
      security.handleLifecycle(AppLifecycleState.paused);
      await tester.pump();
      expect(_runningSplash, findsNothing);
      expect(find.bySemanticsLabel('Wallet settings'), findsNothing);
      security.handleLifecycle(AppLifecycleState.resumed);
      expect(await security.unlock(), isTrue);
      await tester.pump();
      final restarted = tester
          .widget<AnimatedSplashScreen>(_runningSplash)
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
      expect(_runningSplash, findsNothing);
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
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(951, 669);
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    addTearDown(tester.view.reset);
    var attempts = 0;
    final retry = Completer<ProviderContainer>();
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
          return retry.future;
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
    for (final content in [
      find.byIcon(Icons.lock_outline),
      find.text('Wallet could not be opened'),
      find.text('Wallet data could not be opened safely.'),
      find.text('Retry'),
    ]) {
      expect(tester.getCenter(content).dx, 951 / 2);
    }
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
    expect(find.text('Wallet could not be opened'), findsOneWidget);
    expect(_runningSplash, findsNothing);
    expect(
      tester.widget<CustomButton>(find.byType(CustomButton)).loading,
      true,
    );
    await tester.tap(find.byType(CustomButton), warnIfMissed: false);
    expect(attempts, 2);

    retry.complete(ProviderContainer());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Wallet could not be opened'), findsNothing);
  });

  testWidgets('startup offers the command for the persisted deletion stage', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      AppLoader(
        initialize: () async {
          switch (attempts++) {
            case 0:
              throw const AppFailureException(
                AppFailure(
                  code: 'wallet_deletion_incomplete',
                  kind: AppFailureKind.storage,
                  userMessage: 'Wallet removal could not finish.',
                  retryable: false,
                  requiresReconciliation: true,
                ),
              );
            case 1:
              throw const AppFailureException(
                AppFailure(
                  code: 'wallet_deleted_activation_failed',
                  kind: AppFailureKind.storage,
                  userMessage:
                      'Wallet deleted. Try again to open the next wallet.',
                  retryable: false,
                  requiresReconciliation: true,
                ),
              );
            default:
              return ProviderContainer();
          }
        },
        child: const MaterialApp(home: Text('Ready')),
      ),
    );
    await tester.pump();
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.text('Finish removal'));
    await tester.pump();
    expect(find.text('Finish removal'), findsNothing);
    await tester.tap(find.text('Open wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(attempts, 3);
  });

  testWidgets('device unlock remains available during a startup retry', (
    tester,
  ) async {
    final device = _LoaderDevice();
    final security = SecurityController(device);
    addTearDown(security.dispose);
    final prompt = device.nextPrompt();
    var attempts = 0;
    await tester.pumpWidget(
      AppLoader(
        security: security,
        initialize: () async {
          if (attempts++ == 0) {
            throw TimeoutException('Registry temporarily unavailable');
          }
          await security.initialize(hasWallet: true);
          await WidgetsBinding.instance.endOfFrame;
          await security.waitForUnlock();
          return ProviderContainer();
        },
        child: const MaterialApp(home: Text('Ready')),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await _pumpForPrompt(tester, device, 1);
    expect(find.text('Unlock'), findsNothing);

    prompt.complete(DeviceAuthenticationResult.cancelled);
    await tester.pump();
    await tester.pump();
    expect(find.text('Wallet could not be opened'), findsNothing);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
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

SystemUiOverlayStyle _launchSystemStyle(WidgetTester tester) => tester
    .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    )
    .last
    .value;

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

Finder get _runningSplash => find.byWidgetPredicate(
  (widget) =>
      widget is AnimatedSplashScreen &&
      widget.controller is AnimationController,
);

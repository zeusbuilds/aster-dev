import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/core/security/security_gate.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('owned prompt leaves source painted but blocks taps, focus '
      'and semantics until cancellation resumes', (tester) async {
    final device = _HeldDevice();
    addTearDown(device.close);
    final security = SecurityController(device);
    addTearDown(security.dispose);
    await security.initialize(hasWallet: false);
    var taps = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SecurityGate(
          controller: security,
          child: Scaffold(
            body: TextButton(
              focusNode: focus,
              onPressed: () => taps++,
              child: const Text('Source action'),
            ),
          ),
        ),
      ),
    );
    final semantics = tester.ensureSemantics();
    final pending = security.authorize(SecurityPurpose.walletSetup);
    await tester.pump();
    security.handleLifecycle(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Source action'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(
      tester.semantics.simulatedAccessibilityTraversal(),
      isNot(contains(isSemantics(label: 'Source action'))),
    );
    expect(
      TickerMode.valuesOf(find.text('Source action').evaluate().single).enabled,
      isTrue,
    );
    await tester.tap(find.text('Source action'), warnIfMissed: false);
    focus.requestFocus();
    await tester.pump();
    expect(taps, 0);
    expect(focus.hasFocus, isFalse);
    device.prompt.complete(DeviceAuthenticationResult.cancelled);
    await tester.pump();
    expect(security.isAuthenticating, isTrue);
    security.handleLifecycle(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(await pending, isNull);
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.bySemanticsLabel('Source action'), findsOneWidget);
    await tester.tap(find.text('Source action'));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('real background replaces an owned prompt source with privacy '
      'cover immediately', (tester) async {
    final device = _HeldDevice();
    addTearDown(device.close);
    final security = SecurityController(device);
    addTearDown(security.dispose);
    await security.initialize(hasWallet: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SecurityGate(
          controller: security,
          child: const Text('Source action'),
        ),
      ),
    );
    final pending = security.authorize(SecurityPurpose.walletSetup);
    await tester.pump();
    security.handleLifecycle(AppLifecycleState.paused);
    device.background.add(null);
    await tester.pump();
    expect(find.text('Source action'), findsNothing);
    expect(find.byType(SplashScreen), findsOneWidget);
    device.prompt.complete(DeviceAuthenticationResult.authenticated);
    await tester.pump();
    expect(await pending, isNull);
  });

  testWidgets('lock cancellation uses legible controls on shared white art', (
    tester,
  ) async {
    final security = SecurityController(const _SecuredDevice());
    addTearDown(security.dispose);
    await security.initialize(hasWallet: true);
    security.lock();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AsterLockScreen(controller: security),
      ),
    );
    expect(find.byType(SplashScreen), findsOneWidget);
    final title = tester.widget<Text>(find.text('Aster locked'));
    expect(title.style!.color, AppTheme.light().colorScheme.onSurface);
    expect(
      tester.widget<CustomButton>(find.byType(CustomButton)).variant,
      ButtonVariant.primary,
    );
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsNothing);
  });

  testWidgets('warm lock fills viewport after its route is offstage', (
    tester,
  ) async {
    final security = SecurityController(const _SecuredDevice());
    addTearDown(security.dispose);
    await security.initialize(hasWallet: true);
    await security.unlock();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Align(
          alignment: Alignment.topLeft,
          // Deliberately loose constraints reproduce the root builder hierarchy.
          child: SecurityGate(
            controller: security,
            child: const SizedBox(
              width: 100,
              height: 100,
              child: Text('Wallet'),
            ),
          ),
        ),
      ),
    );
    security.lock();
    await tester.pumpAndSettle();
    expect(find.text('Aster locked'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.text('Wallet'), findsNothing);
    expect(find.byType(SplashScreen), findsOneWidget);
    final title = tester.widget<Text>(find.text('Aster locked'));
    expect(title.style!.color, AppTheme.light().colorScheme.onSurface);
    expect(
      tester.widget<CustomButton>(find.byType(CustomButton)).variant,
      ButtonVariant.primary,
    );
    expect(tester.getSize(find.byType(AsterLockScreen)), const Size(800, 600));
    expect(
      tester.getSize(find.widgetWithText(CustomButton, 'Unlock')).width,
      greaterThan(100),
    );
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Unlock'), findsOneWidget);
    semantics.dispose();
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Wallet'), findsOneWidget);
  });
}

final class _HeldDevice
    implements DeviceAuthentication, DeviceAuthenticationBackgroundEvents {
  final prompt = Completer<DeviceAuthenticationResult>();
  final background = StreamController<void>.broadcast(sync: true);
  @override
  Future<DeviceSecurityStatus> status() async => DeviceSecurityStatus.secured;
  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) =>
      prompt.future;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> setSensitive(bool value) async {}
  @override
  Stream<bool> get captureChanges => const Stream.empty();
  @override
  Stream<void> get backgroundEvents => background.stream;
  @override
  bool get isCaptured => false;

  Future<void> close() => background.close();
}

final class _SecuredDevice implements DeviceAuthentication {
  const _SecuredDevice();
  @override
  Future<DeviceSecurityStatus> status() async => DeviceSecurityStatus.secured;
  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) async =>
      DeviceAuthenticationResult.authenticated;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> setSensitive(bool value) async {}
  @override
  Stream<bool> get captureChanges => const Stream.empty();
  @override
  bool get isCaptured => false;
}

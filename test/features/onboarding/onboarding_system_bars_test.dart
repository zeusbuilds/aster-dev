import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/core/security/security_gate.dart';
import 'package:aster/features/onboarding/presentation/screens/onboarding_shell.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'retained blue shell reclaims light bars after white cover and own auth',
    (tester) async {
      final device = _HeldDevice();
      final security = SecurityController(device);
      final covered = ValueNotifier(true);
      addTearDown(security.dispose);
      addTearDown(covered.dispose);
      await security.initialize(hasWallet: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ValueListenableBuilder<bool>(
            valueListenable: covered,
            builder: (context, showCover, _) => Stack(
              fit: StackFit.expand,
              children: [
                SecurityGate(
                  controller: security,
                  child: const OnboardingShell(
                    child: Center(child: Text('Welcome action')),
                  ),
                ),
                if (showCover) const SplashScreen(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.dark,
      );
      expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.light);

      covered.value = false;
      await tester.pumpAndSettle();
      _expectBlueArtworkBars();
      final shellStyle = tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.descendant(
              of: find.byType(OnboardingShell),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            ),
          )
          .value;
      expect(shellStyle.statusBarIconBrightness, Brightness.light);
      expect(shellStyle.statusBarBrightness, Brightness.dark);

      final authorization = security.authorize(SecurityPurpose.walletSetup);
      await tester.pump();
      security.handleLifecycle(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Welcome action'), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
      _expectBlueArtworkBars();

      device.prompt.complete(DeviceAuthenticationResult.authenticated);
      security.handleLifecycle(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(await authorization, isNotNull);
      _expectBlueArtworkBars();
    },
  );
}

void _expectBlueArtworkBars() {
  final style = SystemChrome.latestStyle;
  expect(style, isNotNull);
  expect(style!.statusBarIconBrightness, Brightness.light);
  expect(style.statusBarBrightness, Brightness.dark);
  expect(style.statusBarColor, Colors.transparent);
  expect(style.systemNavigationBarColor, Colors.transparent);
  expect(style.systemNavigationBarIconBrightness, Brightness.light);
}

final class _HeldDevice implements DeviceAuthentication {
  final prompt = Completer<DeviceAuthenticationResult>();

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
  bool get isCaptured => false;
}

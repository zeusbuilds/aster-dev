import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/full_wallet_qa.dart';

void main() {
  testWidgets(
    'QA preserves native auth until actual foreground acknowledgement',
    (tester) async {
      final device = _Device();
      final security = SecurityController(device, appLockEnabled: false);
      addTearDown(security.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await security.initialize(hasWallet: false);
      await tester.pumpWidget(
        FullWalletQaSecurityLifecycle(
          security: security,
          child: const SizedBox.shrink(),
        ),
      );
      SensitiveAuthorization? grant;
      var completed = false;
      final authorization = security
          .authorize(SecurityPurpose.walletSetup)
          .then((value) {
            grant = value;
            completed = true;
          });
      await tester.pump();
      expect(device.prompts, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      device.result.complete(DeviceAuthenticationResult.authenticated);
      await tester.pump();
      expect(completed, isFalse);
      expect(security.isAuthenticating, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await authorization;
      expect(completed, isTrue);
      expect(security.consume(grant, SecurityPurpose.walletSetup), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class _Device implements DeviceAuthentication {
  final result = Completer<DeviceAuthenticationResult>();
  var prompts = 0;

  @override
  Future<DeviceSecurityStatus> status() async => DeviceSecurityStatus.secured;
  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) {
    prompts += 1;
    return result.future;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> setSensitive(bool sensitive) async {}
  @override
  Stream<bool> get captureChanges => const Stream.empty();
  @override
  bool get isCaptured => false;
}

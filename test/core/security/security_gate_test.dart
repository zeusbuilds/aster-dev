import 'package:aster/core/core.dart';
import 'package:aster/core/security/security_gate.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

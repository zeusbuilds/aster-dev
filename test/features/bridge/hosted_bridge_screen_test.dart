import 'dart:async';

import 'package:aster/features/bridge/data/hosted_bridge_store.dart';
import 'package:aster/features/bridge/presentation/hosted_bridge_screen.dart';
import 'package:aster/features/bridge/presentation/view_model/hosted_bridge_controller.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/wallet_fakes.dart';

void main() {
  testWidgets('Dev Bridge waits for restoration and leaves on lost access', (
    tester,
  ) async {
    Completer<void>? restoration;
    final controller = HostedBridgeController(<T>(
      walletId,
      operation,
      authorize,
      allowMutation,
    ) async {
      await restoration?.future;
      authorize();
      return (supported: true, account: 'rgb:utexo:test') as T;
    }, store: HostedBridgeStore(storage: MemorySecureStore()));
    controller.updateOwner(walletId: 'test-wallet', generation: 1);
    final router = GoRouter(
      initialLocation: '/settings/dev-bridge',
      routes: [
        GoRoute(
          path: RoutePaths.settings,
          builder: (_, _) => const Scaffold(body: Text('Settings root')),
          routes: [
            GoRoute(
              path: RoutePaths.hostedBridge,
              builder: (_, _) => const HostedBridgeScreen(),
            ),
          ],
        ),
      ],
    );
    addTearDown(controller.dispose);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostedBridgeControllerProvider.overrideWithValue(controller),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.available, isTrue);
    expect(find.text('Dev Bridge'), findsOneWidget);

    restoration = Completer<void>();
    controller.updateOwner(walletId: 'test-wallet', generation: 2);
    await tester.pumpAndSettle();
    expect(controller.available, isFalse);
    expect(router.state.uri.path, '/settings/dev-bridge');
    restoration.complete();
    await tester.pumpAndSettle();
    expect(controller.available, isTrue);
    expect(router.state.uri.path, '/settings/dev-bridge');

    controller.updateOwner(walletId: null, generation: 3);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, RoutePaths.settings);
    expect(find.text('Settings root'), findsOneWidget);
    expect(find.byType(HostedBridgeScreen), findsNothing);
  });
}

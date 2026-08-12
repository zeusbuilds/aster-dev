import 'dart:ui' as ui;

import 'package:aster/features/market/presentation/screens/market_screen.dart';
import 'package:aster/features/market/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('unsupported market actions are disabled without claims', (
    tester,
  ) async {
    final haptics = _RecordingHaptics();
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, haptics));
    await tester.pumpAndSettle();

    expect(find.text('From 0.1% fee'), findsNothing);
    expect(find.text('Instant payout'), findsNothing);
    expect(find.text('12.4% APY'), findsNothing);
    expect(find.text('Best rate'), findsNothing);
    expect(find.text('Free & instant'), findsNothing);

    for (final label in ['Buy', 'Sell', 'Lend']) {
      final tile = find.widgetWithText(MarketTile, label);
      await tester.scrollUntilVisible(tile, 250);
      expect(
        tester.getSemantics(tile).flagsCollection.isEnabled,
        ui.Tristate.isFalse,
        reason: label,
      );
    }

    final buy = find.widgetWithText(MarketTile, 'Buy');
    await tester.scrollUntilVisible(buy, -250);
    await tester.tap(buy);
    await tester.pumpAndSettle();
    expect(find.text('Market'), findsOneWidget);
    expect(haptics.intents, isEmpty);
  });

  testWidgets('Send and Receive enter typed target-selection routes', (
    tester,
  ) async {
    final haptics = _RecordingHaptics();
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, haptics));
    await tester.pumpAndSettle();

    final send = find.widgetWithText(MarketTile, 'Send');
    await tester.scrollUntilVisible(send, 250);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('Send target selection'), findsOneWidget);
    expect(haptics.intents, [HapticIntent.lightImpact]);

    router.go('/');
    await tester.pumpAndSettle();
    final receive = find.widgetWithText(MarketTile, 'Receive');
    await tester.scrollUntilVisible(receive, 250);
    await tester.tap(receive);
    await tester.pumpAndSettle();
    expect(find.text('Receive target selection'), findsOneWidget);
    expect(haptics.intents, [
      HapticIntent.lightImpact,
      HapticIntent.lightImpact,
    ]);
  });

  testWidgets('Market remains usable on a compact phone at 2x text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(router, _RecordingHaptics(), textScaler: const TextScaler.linear(2)),
    );
    await tester.pumpAndSettle();

    final receive = find.widgetWithText(MarketTile, 'Receive');
    await tester.scrollUntilVisible(receive, 200);
    expect(tester.takeException(), isNull);
    expect(receive, findsOneWidget);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));
  });
}

GoRouter _router() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const MarketScreen()),
      GoRoute(
        path: RoutePaths.send,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Send target selection'))),
      ),
      GoRoute(
        path: RoutePaths.receive,
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Receive target selection')),
        ),
      ),
      GoRoute(
        path: RoutePaths.swap,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Swap preview'))),
      ),
    ],
  );
}

Widget _app(
  GoRouter router,
  HapticFeedbackService haptics, {
  TextScaler? textScaler,
}) {
  return MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: router,
    builder: (context, child) {
      final content = AsterFeedbackScope(
        haptics: haptics,
        toasts: ToastController(),
        child: child!,
      );
      return textScaler == null
          ? content
          : MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: content,
            );
    },
  );
}

final class _RecordingHaptics implements HapticFeedbackService {
  final intents = <HapticIntent>[];

  @override
  Future<void> trigger(HapticIntent intent) async => intents.add(intent);
}

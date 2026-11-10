import 'package:aster/features/market/presentation/screens/market_screen.dart';
import 'package:aster/features/market/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('Market tiles end after the status chip at ${scale}x', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 932);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _app(router, _RecordingHaptics(), textScaler: TextScaler.linear(scale)),
      );
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(MarketTile, 'Send');
      final chip = find.descendant(of: tile, matching: find.byType(AsterPill));
      expect(chip, findsOneWidget);
      expect(
        tester.getBottomLeft(tile).dy - tester.getBottomLeft(chip).dy,
        closeTo(tester.element(tile).spacing.lg, 0.01),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Market has three supported routes without unsupported claims', (
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
    final textures = tester.widgetList<Image>(find.byType(Image));
    expect(textures, isNotEmpty);
    for (final texture in textures) {
      expect(texture.image, isA<ResizeImage>());
      final resized = texture.image as ResizeImage;
      expect(resized.width, inInclusiveRange(1, 600));
      expect(resized.height, resized.width);
    }

    final tiles = tester.widgetList<MarketTile>(find.byType(MarketTile));
    expect(tiles.map((tile) => tile.label), ['Send', 'Receive', 'Swap']);
    final gradients = tester.element(find.byType(MarketScreen)).gradients;
    expect(tiles.map((tile) => tile.gradient), [
      gradients.marketBuy,
      gradients.marketSell,
      gradients.marketSwap,
    ]);
    final white = tester
        .element(find.byType(MarketScreen))
        .appColors
        .onMarketTile;
    for (final tile in tiles) {
      expect(tile.contentTone, MarketContentTone.light);
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.widgetWithText(MarketTile, tile.label),
          matching: find.byType(Text),
        ),
      );
      expect(texts, isNotEmpty);
      expect(texts.every((text) => text.style?.color == white), isTrue);
    }
    for (final label in ['Buy', 'Sell', 'Lend']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('On-chain or Lightning'), findsNothing);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(haptics.intents, isEmpty);
  });

  testWidgets('Market uses a gallery only in open Duo landscape', (
    tester,
  ) async {
    const channel = EventChannel('com.aster.wallet/cover_navigation');
    final messenger = tester.binding.defaultBinaryMessenger;
    late MockStreamHandlerEventSink geometry;
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          geometry = events;
          events.success(null);
        },
      ),
    );
    addTearDown(() => messenger.setMockStreamHandler(channel, null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(951, 669);
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    tester.view.viewPadding = tester.view.padding;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: _app(router, _RecordingHaptics(), useDuoLayout: true),
      ),
    );
    await tester.pumpAndSettle();

    Rect tile(String label) =>
        tester.getRect(find.widgetWithText(MarketTile, label));
    void expectSingleColumn() {
      final send = tile('Send');
      final receive = tile('Receive');
      final swap = tile('Swap');
      expect(receive.left, send.left);
      expect(swap.left, send.left);
      expect(receive.right, send.right);
      expect(swap.right, send.right);
      expect(receive.top, greaterThan(send.bottom));
      expect(swap.top, greaterThan(receive.bottom));
    }

    expectSingleColumn();
    geometry.success({'inner': true, 'width': 951.0, 'height': 669.0});
    await tester.pumpAndSettle();
    final send = tile('Send');
    final receive = tile('Receive');
    final swap = tile('Swap');
    expect(send.top, receive.top);
    expect(send.size, receive.size);
    expect(receive.left - send.right, 16);
    expect(swap.left, send.left);
    expect(swap.right, receive.right);
    expect(swap.top - send.bottom, 16);
    expect(swap.height, lessThan(send.height));
    expect(swap.right, 951 - 84 - 20);

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tile('Send').size, tile('Receive').size);
    expect(tile('Swap').top - tile('Send').bottom, 16);
    for (final label in ['Send', 'Receive', 'Swap']) {
      expect(
        find.widgetWithText(MarketTile, label).hitTestable(),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.clearTextScaleFactorTestValue();

    tester.view.physicalSize = const Size(466, 678);
    geometry.success({'width': 466.0, 'height': 678.0});
    await tester.pumpAndSettle();
    expectSingleColumn();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

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

    router.pop();
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

  testWidgets('Market suppresses same-frame sibling route commands', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final haptics = _RecordingHaptics();
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, haptics));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<MarketTile>(find.byType(MarketTile));
    final swap = tiles.singleWhere((tile) => tile.label == 'Swap');
    final send = tiles.singleWhere((tile) => tile.label == 'Send');
    swap.onTap!();
    send.onTap!();
    await tester.pumpAndSettle();

    expect(find.text('Swap preview'), findsOneWidget);
    expect(find.text('Send target selection'), findsNothing);
    expect(haptics.intents, [HapticIntent.lightImpact]);
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
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
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
  bool useDuoLayout = false,
}) {
  return MaterialApp.router(
    theme: AppTheme.light(),
    routerConfig: router,
    builder: (context, child) {
      final content = AsterFeedbackScope(
        haptics: haptics,
        toasts: ToastController(),
        child: useDuoLayout ? AsterDuoLandscapeScope(child: child!) : child!,
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

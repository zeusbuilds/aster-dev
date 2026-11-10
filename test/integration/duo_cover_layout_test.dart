import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/home/presentation/widgets/widgets.dart';
import 'package:aster/features/market/presentation/widgets/widgets.dart';
import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:aster/features/scan/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/widgets/widgets.dart';
import 'package:aster/main.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/payment_flow_harness.dart';
import '../support/scan_fakes.dart';

const _coverNavigationChannel = EventChannel(
  'com.aster.wallet/cover_navigation',
);
const _closedCover = {'width': 466.0, 'height': 678.0};
const _closedNavigationBounds = {
  ..._closedCover,
  'left': 382.0,
  'top': 162.0,
  'right': 466.0,
  'bottom': 644.0,
};

void main() {
  testWidgets(
    'closed Duo uses the right tab rail and keeps tab selection when opened',
    (tester) async {
      late MockStreamHandlerEventSink geometry;
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        _coverNavigationChannel,
        MockStreamHandler.inline(
          onListen: (_, events) {
            geometry = events;
            events.success(_closedNavigationBounds);
          },
        ),
      );
      _setViewport(tester, size: const Size(466, 678), right: 84);
      await _mountWallet(tester);

      _expectCoverRail(tester);
      final home = _tab('home');
      final settings = _tab('settings');
      final homeHeader = find.byType(HomeHeader);
      expect(tester.getTopLeft(homeHeader).dy, closeTo(12, 0.5));
      _expectSafe(tester, find.widgetWithText(CustomButton, 'Swap'));

      // UIKit can identify the cover even when there's no room for the rail.
      geometry.success(_closedCover);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getCenter(home).dy,
        closeTo(tester.getCenter(settings).dy, 0.5),
      );
      expect(tester.getTopLeft(homeHeader).dy, closeTo(12, 0.5));

      geometry.success(_closedNavigationBounds);
      await tester.pump(const Duration(milliseconds: 400));
      _expectCoverRail(tester);

      await tester.tap(_tab('scan'));
      final manual = find.byType(ScanEnterAddressButton);
      await _waitFor(tester, manual);
      _expectSafe(tester, manual);
      _expectSafe(tester, find.byType(ScanFrame));
      expect(tester.getRect(manual).bottom, closeTo(628, 0.5));

      geometry.success(_closedCover);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(manual).bottom, closeTo(564, 0.5));
      geometry.success(_closedNavigationBounds);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(_tab('market'));
      final sendTile = find.byWidgetPredicate(
        (widget) => widget is MarketTile && widget.label == 'Send',
      );
      await _waitFor(tester, sendTile);
      _expectSafe(tester, sendTile);
      final marketList = find.ancestor(
        of: sendTile,
        matching: find.byType(ListView),
      );
      final market = tester.widget<ListView>(marketList);
      final marketTiles = market.childrenDelegate as SliverChildListDelegate;
      expect((market.padding! as EdgeInsets).bottom, 50);
      expect((marketTiles.children.last as Padding).padding, EdgeInsets.zero);

      await tester.tap(settings);
      final detailsRow = find.widgetWithText(AsterOptionRow, 'Wallet details');
      await _waitFor(tester, detailsRow);
      _expectSafe(tester, detailsRow);

      _resizeViewport(tester, size: const Size(669, 951), top: 82);
      // Flutter can resize before UIKit publishes the open-display update.
      await tester.pump(const Duration(milliseconds: 400));
      final innerHome = tester.getRect(_tab('home'));
      final innerSettings = tester.getRect(settings);
      expect(innerHome.center.dy, closeTo(innerSettings.center.dy, 0.5));
      expect(innerHome.center.dx, lessThan(innerSettings.center.dx));
      expect(tester.widget<Semantics>(settings).properties.selected, isTrue);
      expect(detailsRow.hitTestable(), findsOneWidget);

      geometry.success(null);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(settings), innerSettings);

      await tester.tap(home);
      await _waitFor(tester, homeHeader);
      expect(tester.getTopLeft(homeHeader).dy, closeTo(82, 0.5));
      await tester.tap(settings);
      await _waitFor(tester, detailsRow);

      _resizeViewport(tester, size: const Size(466, 678), right: 84);
      geometry.success(_closedNavigationBounds);
      await tester.pump(const Duration(milliseconds: 400));
      _expectCoverRail(tester);
      expect(tester.widget<Semantics>(settings).properties.selected, isTrue);

      await tester.tap(detailsRow);
      final delete = find.widgetWithText(CustomButton, 'Delete wallet');
      await _waitFor(tester, delete);
      _expectSafe(tester, delete);
      expect(tester.getRect(delete).bottom, closeTo(628, 0.5));
      final list = find.byType(ListView);
      expect(
        tester.widget<ListView>(list).padding,
        const EdgeInsets.only(bottom: 16),
      );

      // Losing the rail should not change the cover insets on a pushed page.
      geometry.success(_closedCover);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.widget<ListView>(list).padding,
        const EdgeInsets.only(bottom: 16),
      );
      expect(tester.getRect(delete).bottom, closeTo(628, 0.5));
      geometry.success(_closedNavigationBounds);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(delete);
      final cancel = find.widgetWithText(CustomButton, 'Cancel');
      await _waitFor(tester, cancel);
      _expectSafe(tester, cancel);
      await tester.tap(cancel);
      await tester.pump(const Duration(milliseconds: 450));
      final router = GoRouter.of(tester.element(delete));
      router.pop();

      final securityRow = find.widgetWithText(AsterOptionRow, 'Security');
      await _waitFor(tester, securityRow);
      await tester.tap(securityRow);
      final lock = find.byKey(const ValueKey('security-lock-now'));
      await _waitFor(tester, lock);
      _expectSafe(tester, lock);
      await tester.tap(lock);
      final unlock = find.widgetWithText(CustomButton, 'Unlock');
      await _waitFor(tester, unlock);
      _expectSafe(tester, unlock);
      expect(tester.getRect(unlock).bottom, closeTo(628, 0.5));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('short cover window keeps Send and Receive actions reachable', (
    tester,
  ) async {
    _setViewport(tester, size: const Size(466, 678), right: 84);
    await _mountWallet(tester);

    await tester.tap(find.widgetWithText(CustomButton, 'Send'));
    final target = find.byWidgetPredicate(
      (widget) =>
          widget is PaymentTargetTile &&
          widget.capability.target == WalletPaymentTarget.bitcoinOnchain,
    );
    await _waitFor(tester, target);
    _expectSafe(tester, target);
    await tester.tap(target);

    final recipient = find.byType(TextField);
    await _waitFor(tester, recipient);
    await tester.enterText(recipient, 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    final next = find.widgetWithText(CustomButton, 'Continue');
    await _reveal(tester, next);
    _expectSafe(tester, next);
    await tester.tap(next);

    final keypad = find.byType(AsterNumericKeypad);
    await _waitFor(tester, keypad);
    _expectSafe(tester, keypad);
    final submit = find.widgetWithText(CustomButton, 'Send');
    await _reveal(tester, submit);
    _expectSafe(tester, submit);

    final router = GoRouter.of(tester.element(submit));
    router.go(RoutePaths.receive);
    await _waitFor(tester, target);
    await tester.tap(target);
    final qr = find.byType(ReceiveRequestQr);
    await _waitFor(tester, qr);
    _expectSafe(tester, qr);
    final share = find.widgetWithText(AsterOptionRow, 'Share');
    await _reveal(tester, share);
    _expectSafe(tester, share);

    final editAmount = find.widgetWithText(AsterOptionRow, 'Set amount');
    await _reveal(tester, editAmount);
    await tester.tap(editAmount);
    final amountSheet = find.byType(ReceiveAmountSheet);
    await _waitFor(tester, amountSheet);
    final digit = find.descendant(of: amountSheet, matching: find.text('1'));
    await _reveal(tester, digit);
    await tester.tap(digit);
    final save = find.descendant(
      of: amountSheet,
      matching: find.widgetWithText(CustomButton, 'Set amount'),
    );
    await _reveal(tester, save);
    _expectSafe(tester, save);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ordinary phones keep the original Home header and bottom navigation',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        _coverNavigationChannel,
        MockStreamHandler.inline(onListen: (_, events) => events.success(null)),
      );
      _setViewport(tester, size: const Size(390, 844), top: 59);
      await _mountWallet(tester);
      final nav = tester
          .getRect(_tab('home'))
          .expandToInclude(tester.getRect(_tab('settings')));
      expect(nav.center.dx, closeTo(195, 0.5));
      expect(nav.bottom, lessThanOrEqualTo(810));
      expect(tester.getTopLeft(find.byType(HomeHeader)).dy, closeTo(59, 0.5));
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}

Finder _tab(String name) => find.byKey(ValueKey('bottom-nav-$name'));

void _expectCoverRail(WidgetTester tester) {
  final tabs = [
    'home',
    'scan',
    'market',
    'settings',
  ].map((name) => tester.getRect(_tab(name))).toList();
  for (var index = 0; index < tabs.length; index++) {
    final rect = tabs[index];
    expect(rect.left, greaterThanOrEqualTo(_closedNavigationBounds['left']!));
    expect(rect.right, lessThanOrEqualTo(_closedNavigationBounds['right']!));
    expect(rect.top, greaterThanOrEqualTo(_closedNavigationBounds['top']!));
    expect(rect.bottom, lessThanOrEqualTo(_closedNavigationBounds['bottom']!));
    expect(rect.width, greaterThanOrEqualTo(44));
    expect(rect.height, greaterThanOrEqualTo(44));
    if (index > 0) {
      final previous = tabs[index - 1];
      expect(rect.center.dx, closeTo(previous.center.dx, 0.5));
      expect(rect.top, greaterThanOrEqualTo(previous.bottom));
    }
  }
}

void _setViewport(
  WidgetTester tester, {
  required Size size,
  double top = 0,
  double right = 0,
}) {
  tester.view.devicePixelRatio = 3;
  _resizeViewport(tester, size: size, top: top, right: right);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

void _resizeViewport(
  WidgetTester tester, {
  required Size size,
  double top = 0,
  double right = 0,
}) {
  final scale = tester.view.devicePixelRatio;
  final padding = FakeViewPadding(
    top: top * scale,
    right: right * scale,
    bottom: 34 * scale,
  );
  tester.view.physicalSize = size * scale;
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
}

void _expectSafe(WidgetTester tester, Finder control) {
  final rect = tester.getRect(control);
  expect(rect.left, greaterThanOrEqualTo(0), reason: '$control');
  expect(rect.right, lessThanOrEqualTo(382), reason: '$control');
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var frame = 0; frame < 100 && finder.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsOneWidget);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await _waitFor(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 400));
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> _mountWallet(WidgetTester tester) async {
  const auth = MethodChannel('com.aster.wallet/device_authentication');
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(auth, (call) async {
    if (call.method == 'getStatus') return {'secured': true, 'captured': false};
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(auth, null));

  final transport = ResilientHttpClient(
    client: MockClient((_) async => http.Response('{}', 503)),
    retryPolicy: RetryPolicy(maxAttempts: 1),
  );
  addTearDown(transport.close);
  final harness = await PaymentFlowTestHarness.create(
    services: testRgbServices,
    httpClient: transport,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    final disposal = harness.dispose();
    await tester.pump();
    await disposal;
  });

  await harness.container
      .read(securityControllerProvider)
      .initialize(hasWallet: false);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: ProviderScope(
        overrides: [
          scanSessionProvider(ScanPurpose.sendLauncher).overrideWith((ref) {
            final session = FakeScanSession();
            ref.onDispose(() => unawaited(session.close()));
            return session;
          }),
        ],
        child: const AsterApp(),
      ),
    ),
  );
  final home = _tab('home');
  await _waitFor(tester, home);
  final animation = ModalRoute.of(tester.element(home))!.animation!;
  for (var frame = 0; frame < 50 && animation.isAnimating; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(animation.isCompleted, isTrue);
}

import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/home/presentation/widgets/widgets.dart';
import 'package:aster/features/market/presentation/widgets/widgets.dart';
import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:aster/features/scan/presentation/widgets/widgets.dart';
import 'package:aster/features/send/presentation/widgets/widgets.dart';
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
const _closedRailBand = Rect.fromLTRB(382, 162, 466, 644);
const _openLandscape = {'inner': true, 'width': 951.0, 'height': 669.0};
const _openNavigationBounds = {
  ..._openLandscape,
  'left': 867.0,
  'top': 162.0,
  'right': 951.0,
  'bottom': 635.0,
};
const _openRailBand = Rect.fromLTRB(867, 162, 951, 635);

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

      _expectVerticalRail(tester, _closedRailBand);
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
      _expectVerticalRail(tester, _closedRailBand);

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
      _expectVerticalRail(tester, _closedRailBand);
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

  testWidgets('open Duo Send switches assets and keeps its recipient on fold', (
    tester,
  ) async {
    late MockStreamHandlerEventSink geometry;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      _coverNavigationChannel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          geometry = events;
          events.success(_openNavigationBounds);
        },
      ),
    );
    addTearDown(
      () => messenger.setMockStreamHandler(_coverNavigationChannel, null),
    );
    _setViewport(tester, size: const Size(951, 669), right: 84);
    await _mountWallet(tester);

    Finder tile(WalletPaymentTarget target) => find.byWidgetPredicate(
      (widget) =>
          widget is PaymentTargetTile && widget.capability.target == target,
    );
    Finder recipientCard(WalletPaymentTarget target) => find.byWidgetPredicate(
      (widget) =>
          widget is SendAddressCard &&
          widget.target == target &&
          widget.enabled,
    );
    Finder recipientField(Finder card) =>
        find.descendant(of: card, matching: find.byType(TextField));
    const bitcoin = WalletPaymentTarget.bitcoinOnchain;
    const usdt = WalletPaymentTarget.usdtOnchain;
    const address = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
    final bitcoinCard = recipientCard(bitcoin);
    final usdtCard = recipientCard(usdt);
    final bitcoinField = recipientField(bitcoinCard);

    await tester.tap(find.widgetWithText(CustomButton, 'Send'));
    await _waitFor(tester, bitcoinCard);
    final router = GoRouter.of(tester.element(bitcoinCard));
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      RoutePaths.send,
    );
    expect(
      tester.getRect(tile(bitcoin)).right,
      lessThan(tester.getRect(bitcoinCard).left),
    );
    expect(
      tester.getRect(bitcoinCard).right,
      lessThanOrEqualTo(_openRailBand.left),
    );
    expect(usdtCard, findsNothing);

    for (final target in [
      WalletPaymentTarget.bitcoinLightning,
      WalletPaymentTarget.usdtLightning,
    ]) {
      final disabled = tile(target);
      final action = find.descendant(
        of: disabled,
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(action).onTap, isNull);
      await tester.tap(disabled, warnIfMissed: false);
      await tester.pump();
      expect(bitcoinCard, findsOneWidget);
    }

    await tester.tap(tile(usdt));
    await _waitFor(tester, usdtCard);
    expect(bitcoinCard, findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      RoutePaths.send,
    );
    await tester.enterText(recipientField(usdtCard), 'rgb:usdt-draft');
    await tester.pump();
    await tester.tap(tile(bitcoin));
    await _waitFor(tester, bitcoinCard);
    expect(tester.widget<TextField>(bitcoinField).controller!.text, isEmpty);

    await tester.enterText(bitcoinField, address);
    final next = find.widgetWithText(CustomButton, 'Continue');
    await _reveal(tester, next);
    await tester.tap(next);
    await _waitFor(tester, find.byType(AsterNumericKeypad));
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/send/bitcoin-onchain/amount',
    );

    await tester.binding.handlePopRoute();
    await _waitFor(tester, bitcoinCard);
    expect(tester.widget<TextField>(bitcoinField).controller!.text, address);
    expect(tile(bitcoin), findsOneWidget);

    _resizeViewport(tester, size: const Size(466, 678), right: 84);
    geometry.success(_closedNavigationBounds);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tile(bitcoin), findsNothing);
    expect(tester.widget<TextField>(bitcoinField).controller!.text, address);
    _expectSafe(tester, bitcoinCard);

    await tester.binding.handlePopRoute();
    await _waitFor(tester, tile(bitcoin));
    expect(bitcoinCard, findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      RoutePaths.send,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('open Duo Receive preserves each asset request across switches', (
    tester,
  ) async {
    late MockStreamHandlerEventSink geometry;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      _coverNavigationChannel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          geometry = events;
          events.success(_openNavigationBounds);
        },
      ),
    );
    addTearDown(
      () => messenger.setMockStreamHandler(_coverNavigationChannel, null),
    );
    _setViewport(tester, size: const Size(951, 669), right: 84);
    final harness = await _mountWallet(tester);

    Finder tile(WalletPaymentTarget target) => find.byWidgetPredicate(
      (widget) =>
          widget is PaymentTargetTile && widget.capability.target == target,
    );
    Finder request(WalletAssetKind asset) => find.byWidgetPredicate(
      (widget) => widget is ReceiveRequestQr && widget.assetKind == asset,
    );
    int requestCount() => harness.engine.calls
        .where((call) => call == 'createReceiveRequest:start')
        .length;
    const bitcoin = WalletPaymentTarget.bitcoinOnchain;
    const usdt = WalletPaymentTarget.usdtOnchain;
    final bitcoinQr = request(WalletAssetKind.bitcoin);
    final usdtQr = request(WalletAssetKind.usdt);

    await tester.tap(find.widgetWithText(CustomButton, 'Receive'));
    await _waitFor(tester, bitcoinQr);
    final router = GoRouter.of(tester.element(bitcoinQr));
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      RoutePaths.receive,
    );
    expect(
      tester.getRect(tile(bitcoin)).right,
      lessThan(tester.getRect(bitcoinQr).left),
    );
    expect(
      tester.getRect(bitcoinQr).right,
      lessThanOrEqualTo(_openRailBand.left),
    );
    expect(usdtQr, findsNothing);
    expect(requestCount(), 1);
    final bitcoinRequest = tester
        .widget<ReceiveRequestQr>(bitcoinQr)
        .encodedRequest;

    for (final target in [
      WalletPaymentTarget.bitcoinLightning,
      WalletPaymentTarget.usdtLightning,
    ]) {
      final disabled = tile(target);
      final action = find.descendant(
        of: disabled,
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(action).onTap, isNull);
      await tester.tap(disabled, warnIfMissed: false);
      await tester.pump();
      expect(bitcoinQr, findsOneWidget);
      expect(requestCount(), 1);
    }

    await tester.tap(tile(usdt));
    await _waitFor(tester, usdtQr);
    expect(bitcoinQr, findsNothing);
    expect(requestCount(), 2);
    expect(harness.engine.createdReceiveRoute?.target, usdt);
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      RoutePaths.receive,
    );

    final setAmount = find.widgetWithText(AsterOptionRow, 'Set amount');
    await _reveal(tester, setAmount);
    await tester.tap(setAmount);
    final sheet = find.byType(ReceiveAmountSheet);
    await _waitFor(tester, sheet);
    expect(tester.widget<ReceiveAmountSheet>(sheet).target, usdt);
    final digit = find.descendant(of: sheet, matching: find.text('1'));
    await _reveal(tester, digit);
    await tester.tap(digit);
    final apply = find.descendant(
      of: sheet,
      matching: find.widgetWithText(CustomButton, 'Set amount'),
    );
    await _reveal(tester, apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(requestCount(), 3);
    expect(harness.engine.createdReceiveRoute?.target, usdt);
    expect(harness.engine.createdReceiveAmount?.units, 1000000);

    await tester.tap(tile(bitcoin));
    await _waitFor(tester, bitcoinQr);
    expect(
      tester.widget<ReceiveRequestQr>(bitcoinQr).encodedRequest,
      bitcoinRequest,
    );
    expect(requestCount(), 3);

    await tester.tap(tile(usdt));
    await _waitFor(tester, usdtQr);
    expect(requestCount(), 3);
    final usdtRequest = tester.widget<ReceiveRequestQr>(usdtQr).encodedRequest;
    _resizeViewport(tester, size: const Size(466, 678), right: 84);
    geometry.success(_closedNavigationBounds);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tile(bitcoin), findsNothing);
    expect(tester.widget<ReceiveRequestQr>(usdtQr).encodedRequest, usdtRequest);
    expect(requestCount(), 3);
    _expectSafe(tester, usdtQr);

    await tester.binding.handlePopRoute();
    await _waitFor(tester, tile(bitcoin));
    expect(usdtQr, findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      RoutePaths.receive,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('open Duo Settings keeps the options list to the left', (
    tester,
  ) async {
    late MockStreamHandlerEventSink geometry;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      _coverNavigationChannel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          geometry = events;
          events.success(_openNavigationBounds);
        },
      ),
    );
    addTearDown(
      () => messenger.setMockStreamHandler(_coverNavigationChannel, null),
    );
    _setViewport(tester, size: const Size(951, 669), right: 84);
    await _mountWallet(tester);

    Finder option(String title) => find.widgetWithText(AsterOptionRow, title);
    final settingsTab = _tab('settings');
    final walletDetails = option('Wallet details');
    final security = option('Security');
    final bitcoinUnit = option('Bitcoin unit');
    final delete = find.widgetWithText(CustomButton, 'Delete wallet');
    final appLock = find.byKey(const ValueKey('security-app-lock-switch'));
    await tester.tap(settingsTab);
    await _waitFor(tester, delete);
    final router = GoRouter.of(tester.element(settingsTab));

    void expectRightPane(Finder control) {
      final bounds = tester.getRect(control);
      expect(bounds.left, greaterThan(tester.getRect(walletDetails).right));
      expect(bounds.right, lessThanOrEqualTo(_openRailBand.left));
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        RoutePaths.home,
      );
    }

    expectRightPane(delete);
    for (final row in [
      walletDetails,
      security,
      option('Advanced'),
      bitcoinUnit,
      option('Currency'),
      option('Language'),
    ]) {
      final bounds = tester.getRect(row);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThan(951 / 2));
    }

    await tester.tap(security);
    await _waitFor(tester, appLock);
    expectRightPane(appLock);
    expect(find.byKey(const ValueKey('security-lock-now')), findsOneWidget);
    expect(delete, findsNothing);
    expect(security.hitTestable(), findsOneWidget);

    await _reveal(tester, bitcoinUnit);
    await tester.tap(bitcoinUnit);
    final satoshis = find.text('Satoshis');
    await _waitFor(tester, satoshis);
    expectRightPane(satoshis);
    await tester.tap(satoshis);
    await tester.pumpAndSettle();
    expect(satoshis, findsNothing);
    expect(tester.widget<AsterOptionRow>(bitcoinUnit).details, 'sats');
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      RoutePaths.home,
    );

    if (appLock.evaluate().isEmpty) {
      await _reveal(tester, security);
      await tester.tap(security);
      await _waitFor(tester, appLock);
    }
    _resizeViewport(tester, size: const Size(466, 678), right: 84);
    geometry.success(_closedNavigationBounds);
    await tester.pump(const Duration(milliseconds: 400));
    expect(appLock, findsNothing);
    expect(delete, findsNothing);
    _expectSafe(tester, walletDetails);
    _expectSafe(tester, bitcoinUnit);

    _resizeViewport(tester, size: const Size(951, 669), right: 84);
    geometry.success(_openNavigationBounds);
    await _waitFor(tester, appLock);
    expectRightPane(appLock);
    expect(tester.widget<AsterOptionRow>(bitcoinUnit).details, 'sats');

    final optionsBounds = tester.getRect(walletDetails);
    await tester.tap(_tab('home'));
    await _waitFor(tester, find.byType(HomeHeader));
    await tester.tap(settingsTab);
    await _waitFor(tester, delete);
    expectRightPane(delete);
    expect(appLock, findsNothing);
    expect(tester.getRect(walletDetails), optionsBounds);
    expect(tester.widget<AsterOptionRow>(bitcoinUnit).details, 'sats');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('open Duo landscape splits Home and bottom-aligns the controls', (
    tester,
  ) async {
    late MockStreamHandlerEventSink geometry;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      _coverNavigationChannel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          geometry = events;
          events.success(null);
        },
      ),
    );
    addTearDown(
      () => messenger.setMockStreamHandler(_coverNavigationChannel, null),
    );
    _setViewport(tester, size: const Size(951, 669), right: 84);
    await _mountWallet(tester);

    final homeHeader = find.byType(HomeHeader);
    final price = find.byType(PriceCard);
    final assets = find.byType(AssetsSection);
    final actions = find.byType(HomeActionButtons);
    final priceState = tester.state(price);
    final assetsState = tester.state(assets);
    final compactPriceHeight = tester.getSize(price).height;
    expect(tester.getTopLeft(homeHeader).dy, 0);
    final marketTab = _tab('market');
    await tester.tap(marketTab);
    final marketTitle = find.text('Market');
    await _waitFor(tester, marketTitle);
    final titleTop = tester.getTopLeft(marketTitle).dy;

    geometry.success(_openLandscape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getTopLeft(marketTitle).dy, closeTo(titleTop + 12, 0.5));
    expect(tester.widget<Semantics>(marketTab).properties.selected, isTrue);
    final sendTile = find.byWidgetPredicate(
      (widget) => widget is MarketTile && widget.label == 'Send',
    );
    final marketList = find.ancestor(
      of: sendTile,
      matching: find.byType(ListView),
    );
    final list = tester.widget<ListView>(marketList);
    expect((list.padding! as EdgeInsets).bottom, 34 + 64 + 16);
    final tiles = list.childrenDelegate as SliverChildListDelegate;
    expect((tiles.children.last as MarketTile).label, 'Swap');
    expect(tester.getRect(marketTab).bottom, closeTo(669 - 34 - 8, 0.5));

    geometry.success(_openNavigationBounds);
    await tester.pump(const Duration(milliseconds: 400));
    _expectVerticalRail(tester, _openRailBand);
    expect(
      tester.getRect(_tab('settings')).bottom,
      closeTo(_openRailBand.bottom - 8, 0.5),
    );
    expect(tester.widget<Semantics>(marketTab).properties.selected, isTrue);
    expect(
      (tester.widget<ListView>(marketList).padding! as EdgeInsets).bottom,
      34 + 16,
    );

    await tester.tap(_tab('home'));
    await _waitFor(tester, homeHeader);
    expect(tester.getTopLeft(homeHeader).dy, closeTo(12, 0.5));
    final assetsBounds = tester.getRect(assets);
    expect(assetsBounds.top, closeTo(12, 0.5));
    expect(assetsBounds.right, lessThanOrEqualTo(_openRailBand.left));
    for (final chartControl in [homeHeader, price]) {
      expect(
        tester.getRect(chartControl).right,
        lessThanOrEqualTo(assetsBounds.left),
      );
    }
    final actionButtons = [
      for (final label in ['Send', 'Receive', 'Swap'])
        find.descendant(
          of: actions,
          matching: find.widgetWithText(CustomButton, label),
        ),
    ];
    final stackedButtons = actionButtons.map(tester.getRect).toList();
    final chartBounds = tester.getRect(price);
    expect(stackedButtons.first.top, greaterThan(chartBounds.bottom));
    expect(stackedButtons.last.bottom, closeTo(669 - 34 - 16, 0.5));
    for (var index = 0; index < stackedButtons.length; index++) {
      final button = stackedButtons[index];
      expect(button.left, greaterThanOrEqualTo(chartBounds.left));
      expect(button.right, lessThanOrEqualTo(chartBounds.right));
      expect(button.right, lessThan(assetsBounds.left));
      expect(button.left, closeTo(stackedButtons.first.left, 0.5));
      expect(button.width, closeTo(stackedButtons.first.width, 0.5));
      if (index > 0) {
        expect(button.top, greaterThan(stackedButtons[index - 1].bottom));
      }
      expect(
        tester.widget<CustomButton>(actionButtons[index]).variant,
        ButtonVariant.translucent,
      );
      expect(actionButtons[index].hitTestable(), findsOneWidget);
    }
    expect(tester.getSize(price).height, greaterThan(compactPriceHeight));
    expect(tester.state(price), same(priceState));
    expect(tester.state(assets), same(assetsState));

    // The split depends on the viewport, even when no safe rail is reported.
    geometry.success(_openLandscape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getRect(assets), assetsBounds);
    final fallbackButtons = actionButtons.map(tester.getRect).toList();
    expect(
      fallbackButtons.last.bottom,
      closeTo(stackedButtons.last.bottom - 64, 0.5),
    );
    for (var index = 0; index < fallbackButtons.length; index++) {
      expect(fallbackButtons[index].size, stackedButtons[index].size);
      expect(fallbackButtons[index].left, stackedButtons[index].left);
      expect(actionButtons[index].hitTestable(), findsOneWidget);
    }
    expect(tester.getCenter(_tab('home')).dy, tester.getCenter(marketTab).dy);

    // A short inner window still reaches the footer through its own scroll.
    _resizeViewport(tester, size: const Size(951, 420), right: 84);
    geometry.success({..._openNavigationBounds, 'height': 420, 'bottom': 386});
    await tester.pump(const Duration(milliseconds: 400));
    final leftScroll = Scrollable.of(tester.element(actionButtons.last));
    expect(leftScroll.position.maxScrollExtent, greaterThan(0));
    leftScroll.position.jumpTo(leftScroll.position.maxScrollExtent);
    await tester.pump();
    expect(actionButtons.last.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(actionButtons.last).bottom,
      closeTo(420 - 34 - 16, 0.5),
    );
    expect(tester.getRect(assets).top, closeTo(assetsBounds.top, 0.5));

    // Stale wide geometry cannot retain the rail or split on inner portrait.
    geometry.success(_openNavigationBounds);
    _resizeViewport(tester, size: const Size(669, 951), top: 82);
    await tester.pump();
    expect(tester.getTopLeft(homeHeader).dy, closeTo(82, 0.5));
    expect(
      tester.getRect(assets).top,
      greaterThanOrEqualTo(tester.getRect(actions).bottom),
    );
    final portraitButtons = actionButtons.map(tester.getRect).toList();
    for (var index = 1; index < portraitButtons.length; index++) {
      expect(
        portraitButtons[index].top,
        closeTo(portraitButtons.first.top, 0.5),
      );
      expect(
        portraitButtons[index].left,
        greaterThan(portraitButtons[index - 1].right),
      );
    }
    expect(tester.getCenter(_tab('home')).dy, tester.getCenter(marketTab).dy);
    expect(tester.state(price), same(priceState));
    expect(tester.state(assets), same(assetsState));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

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
      expect(
        tester.getRect(find.byType(HomeActionButtons)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(AssetsSection)).top),
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}

Finder _tab(String name) => find.byKey(ValueKey('bottom-nav-$name'));

void _expectVerticalRail(WidgetTester tester, Rect band) {
  final tabs = [
    'home',
    'scan',
    'market',
    'settings',
  ].map((name) => tester.getRect(_tab(name))).toList();
  for (var index = 0; index < tabs.length; index++) {
    final rect = tabs[index];
    expect(rect.left, greaterThanOrEqualTo(band.left));
    expect(rect.right, lessThanOrEqualTo(band.right));
    expect(rect.top, greaterThanOrEqualTo(band.top));
    expect(rect.bottom, lessThanOrEqualTo(band.bottom));
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
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

Future<PaymentFlowTestHarness> _mountWallet(WidgetTester tester) async {
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
  return harness;
}

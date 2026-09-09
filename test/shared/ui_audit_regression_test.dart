import 'dart:convert';
import 'dart:ui' as ui;

import 'package:aster/features/home/presentation/widgets/asset_row.dart';
import 'package:aster/features/home/presentation/widgets/home_header.dart';
import 'package:aster/features/market/presentation/widgets/market_tile.dart';
import 'package:aster/features/onboarding/presentation/widgets/onboarding_import_wallet_word_grid.dart';
import 'package:aster/features/scan/presentation/widgets/scan_enter_address_button.dart';
import 'package:aster/features/send/presentation/screens/send_address_screen.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/settings/presentation/screens/settings_screen.dart';
import 'package:aster/features/shell/presentation/providers/app_shell_index_provider.dart';
import 'package:aster/features/shell/presentation/screens/app_shell_screen.dart';
import 'package:aster/features/swap/presentation/widgets/swap_pair.dart';
import 'package:aster/features/transaction/presentation/formatting/formatting.dart';
import 'package:aster/features/transaction/presentation/widgets/transaction_item.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/payment_flow_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final manifest = (jsonDecode(
      await rootBundle.loadString('FontManifest.json'),
    ) as List<dynamic>).cast<Map<String, dynamic>>();
    for (final entry in manifest) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  testWidgets('UXA-001 semantic activation reaches each enabled command once', (
    tester,
  ) async {
    var calls = 0;
    for (final control in <Widget>[
      AssetRow(
        kind: WalletAssetKind.bitcoin,
        title: 'Bitcoin',
        totalText: '1 sats',
        availableText: '1 sats',
        fiatContext: 'Unavailable',
        balancesVisible: true,
        onTap: () => calls++,
      ),
      SwapPair(
        label: 'From',
        target: WalletPaymentTarget.bitcoinOnchain,
        onTap: () => calls++,
      ),
      MarketTile(
        label: 'Receive',
        icon: Icons.south_west,
        gradient: AsterGradients.light.marketReceive,
        hapticIntent: null,
        onTap: () => calls++,
      ),
    ]) {
      await _mount(tester, control);
      final node = tester.getSemantics(find.byWidget(control));
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      final before = calls;
      node.owner!.performAction(node.id, ui.SemanticsAction.tap);
      await tester.pump();
      expect(calls, before + 1);
      final ink = find.descendant(
        of: find.byWidget(control),
        matching: find.byType(InkWell),
      );
      tester.widget<InkWell>(ink).onTap!();
      expect(calls, before + 2);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, before + 3);
    }
    await _mount(
      tester,
      AssetRow(
        kind: WalletAssetKind.bitcoin,
        title: 'Bitcoin',
        totalText: '1 sats',
        availableText: '1 sats',
        fiatContext: 'Unavailable',
        balancesVisible: true,
        loading: true,
        onTap: () => calls++,
      ),
    );
    expect(
      tester
          .getSemantics(find.byType(AssetRow))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    await _mount(
      tester,
      MarketTile(
        label: 'Unavailable',
        icon: Icons.block,
        gradient: AsterGradients.light.marketSend,
      ),
    );
    expect(
      tester
          .getSemantics(find.byType(MarketTile))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
  });

  testWidgets('UXA-001 wallet header semantics opens the guarded route', (
    tester,
  ) async {
    final h = await PaymentFlowTestHarness.create();
    addTearDown(() => _dispose(tester, h));
    var opens = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: AsterNavigationScope(child: HomeHeader())),
        ),
        GoRoute(
          path: '/wallets',
          name: RouteNames.walletSelection,
          builder: (_, _) {
            opens++;
            return const Scaffold(body: Text('Wallet choices'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await _settleData(tester);
    final node = tester.getSemantics(
      find.bySemanticsLabel('Select wallet, Active'),
    );
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(find.text('Wallet choices'), findsOneWidget);
  });

  testWidgets(
    'UXA-002 exact amounts scroll without truncation or moving the keypad',
    (tester) async {
      for (final (kind, unit, value) in [
        (WalletAssetKind.bitcoin, 'BTC', '0.12345678'),
        (WalletAssetKind.bitcoin, 'sats', '2100000000000000'),
        (WalletAssetKind.usdt, 'USDT', '18446744073709.551615'),
      ]) {
        for (final scale in [1.0, 2.0]) {
          Widget surface(String value) => Column(
            children: [
              WalletAmountEntry(value: value, unit: unit, assetKind: kind),
              const SizedBox(key: ValueKey('keypad-anchor'), height: 48),
            ],
          );
          await _mount(
            tester,
            surface('1'),
            scale: scale,
            size: const Size(320, 568),
          );
          final y = tester
              .getTopLeft(find.byKey(const ValueKey('keypad-anchor')))
              .dy;
          await _mount(
            tester,
            surface(value),
            scale: scale,
            size: const Size(320, 568),
          );
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('keypad-anchor'))).dy,
            y,
          );
          final rich = find.descendant(
            of: find.byType(NumericText),
            matching: find.byType(RichText),
          );
          final paragraph = tester.renderObject<RenderParagraph>(rich);
          expect(paragraph.text.toPlainText(), value);
          expect(paragraph.didExceedMaxLines, isFalse);
          final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
          if (scale == 2) {
            expect(scroll.position.maxScrollExtent, greaterThan(0));
          }
          expect(scroll.position.pixels, scroll.position.maxScrollExtent);
          scroll.position.jumpTo(0);
          await tester.pump();
          expect(scroll.position.pixels, 0);
          expect(find.bySemanticsLabel('Amount, $value $unit'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'UXA-003 recovery words traverse 1 through 12 without changing columns',
    (tester) async {
      final words = List.generate(12, (i) => 'word${i + 1}');
      await _mount(tester, OnboardingImportWalletWordGrid(words: words));
      final labels = <String>[];
      void visit(SemanticsNode node) {
        if (RegExp(r'^\d+\. word\d+$').hasMatch(node.label)) {
          labels.add(node.label);
        }
        for (final child in node.debugListChildrenInOrder(
          DebugSemanticsDumpOrder.traversalOrder,
        )) {
          visit(child);
        }
      }

      visit(tester.getSemantics(find.byType(OnboardingImportWalletWordGrid)));
      expect(labels, List.generate(12, (i) => '${i + 1}. word${i + 1}'));
      expect(
        tester.getTopLeft(find.text('word1')).dy,
        tester.getTopLeft(find.text('word7')).dy,
      );
      expect(
        tester.getTopLeft(find.text('word1')).dx,
        lessThan(tester.getTopLeft(find.text('word7')).dx),
      );
    },
  );

  testWidgets(
    'UXA-004 repeated tab switches preserve scroll and widget state',
    (tester) async {
      final h = await PaymentFlowTestHarness.create();
      addTearDown(() => _dispose(tester, h));
      h.container.read(appShellIndexProvider.notifier).setIndex(3);
      await _mount(
        tester,
        UncontrolledProviderScope(
          container: h.container,
          child: const AppShellScreen(),
        ),
      );
      await _settleData(tester);
      final scrollFinder = find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      final before = tester.state<ScrollableState>(scrollFinder);
      before.position.jumpTo(150);
      for (var i = 0; i < 4; i++) {
        h.container.read(appShellIndexProvider.notifier).setIndex(2);
        await tester.pump();
        h.container.read(appShellIndexProvider.notifier).setIndex(3);
        await tester.pump();
        final after = tester.state<ScrollableState>(scrollFinder);
        expect(identical(before, after), isTrue);
        expect(after.position.pixels, 150);
      }
    },
  );

  testWidgets('UXA-005 transaction amounts share the actual trailing edge', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      for (final units in [1, 100000000]) {
        for (final visible in [true, false]) {
          final record = WalletActivity(
            id: 'activity-${'a' * 64}',
            txid: 'a' * 64,
            source: WalletActivitySource.bitcoinTransaction,
            operation: WalletActivityOperation.bitcoinReceive,
            asset: WalletAsset.bitcoin,
            rail: PaymentRail.onchain,
            direction: WalletActivityDirection.received,
            status: WalletActivityStatus.pending,
            amount: WalletAmount.onchain(
              assetId: WalletAsset.bitcoin.id,
              units: units,
            ),
            occurredAt: DateTime.utc(2026, 9, 9),
          );
          await _mount(
            tester,
            TransactionItem(
              activity: record,
              bitcoinUnit: BitcoinUnit.sats,
              valuesVisible: visible,
              formatter: ActivityDisplayFormatter(),
            ),
            scale: scale,
          );
          expect(
            tester.getRect(find.byType(AmountText)).right,
            tester.getRect(find.byType(TransactionItem)).right,
          );
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets(
    'UXA-006 remount and target change hydrate the correct destination',
    (tester) async {
      final h = await PaymentFlowTestHarness.create();
      addTearDown(() => _dispose(tester, h));
      const target = WalletPaymentTarget.bitcoinOnchain;
      final provider = sendFlowViewModelProvider(target);
      final sub = h.container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      await h.container.read(provider.future);
      const destination = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
      h.container.read(provider.notifier).updateDestination(destination);
      await _mount(
        tester,
        UncontrolledProviderScope(
          container: h.container,
          child: const SendAddressScreen(target: target),
        ),
      );
      await _settleData(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        destination,
      );
      expect(
        await h.container.read(provider.notifier).validateDestination(),
        isTrue,
      );
      await _mount(
        tester,
        UncontrolledProviderScope(
          container: h.container,
          child: const SendAddressScreen(
            target: WalletPaymentTarget.bitcoinLightning,
          ),
        ),
      );
      await _settleData(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await _mount(
        tester,
        UncontrolledProviderScope(
          container: h.container,
          child: const SendAddressScreen(target: target),
        ),
      );
      await _settleData(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        destination,
      );
    },
  );

  test(
    'UXA-007/008 readable semantic foregrounds reuse the existing palette',
    () {
      final colors = AsterColors.light;
      final scheme = AsterColors.lightColorScheme();
      for (final surface in [
        colors.successContainer,
        colors.warningContainer,
        colors.dangerContainer,
        scheme.surface,
      ]) {
        expect(
          _contrast(colors.statusForeground, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(
        _contrast(colors.onMarketTile, scheme.onSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(colors.statusForeground, scheme.onSurface);
      expect(colors.copyWith().statusForeground, colors.statusForeground);
      expect(
        colors
            .lerp(colors.copyWith(statusForeground: scheme.primary), 1)
            .statusForeground,
        scheme.primary,
      );
      for (final surface in AsterGradients.light.marketReceive.colors) {
        expect(
          _contrast(colors.marketDarkText, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'UXA-008 active Market contrast at ${scale}x with authored artwork',
      (tester) async {
        for (final (label, gradient, tone) in [
          (
            'Receive',
            AsterGradients.light.marketReceive,
            MarketContentTone.dark,
          ),
          ('Send', AsterGradients.light.marketSend, MarketContentTone.dark),
          ('Swap', AsterGradients.light.marketSwap, MarketContentTone.light),
        ]) {
          await _mount(
            tester,
            MarketTile(
              label: label,
              subtitle: 'Bitcoin or USDT',
              tipText: 'On-chain or Lightning',
              icon: Icons.call_made,
              gradient: gradient,
              contentTone: tone,
              hapticIntent: null,
              onTap: () {},
            ),
            scale: scale,
            size: const Size(320, 568),
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'UXA-012 option monetary details keep units and identifiers in DM Sans',
    (tester) async {
      await _mount(
        tester,
        const Column(
          children: [
            AsterOptionRow(
              title: 'Set amount',
              amountDetails: '0.12345678 BTC',
            ),
            AsterOptionRow(title: 'Identifier', details: 'abc123'),
          ],
        ),
        scale: 2,
        size: const Size(320, 568),
      );
      final amount = tester.widget<RichText>(
        find.descendant(
          of: find.byType(AmountText),
          matching: find.byType(RichText),
        ),
      );
      final spans = <TextSpan>[];
      void collect(InlineSpan span) {
        if (span is! TextSpan) return;
        if (span.text != null) spans.add(span);
        for (final child in span.children ?? const <InlineSpan>[]) {
          collect(child);
        }
      }

      collect(amount.text);
      expect(spans.first.style!.fontFamily, 'Public Sans');
      expect(spans.last.text, ' BTC');
      expect(spans.last.style!.fontFamily, 'DM Sans');
      expect(
        tester.widget<Text>(find.text('abc123')).style!.fontFamily,
        'DM Sans',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('UXA-014 scanner manual control has a live 48px edge target', (
    tester,
  ) async {
    var calls = 0;
    await _mount(tester, ScanEnterAddressButton(onTap: () => calls++));
    final rect = tester.getRect(find.byType(ScanEnterAddressButton));
    expect(rect.height, greaterThanOrEqualTo(48));
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 1));
    expect(calls, 1);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(iOSTapTargetGuideline));
  });
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return ((first > second ? first : second) + 0.05) /
      ((first > second ? second : first) + 0.05);
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _settleData(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _dispose(WidgetTester tester, PaymentFlowTestHarness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final done = h.dispose();
  await tester.pump();
  await done;
}

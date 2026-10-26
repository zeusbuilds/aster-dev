import 'dart:ui' as ui;

import 'package:aster/features/send/presentation/widgets/widgets.dart';
import 'package:aster/features/settings/domain/models/models.dart';
import 'package:aster/features/settings/presentation/models/models.dart';
import 'package:aster/features/settings/presentation/widgets/widgets.dart';
import 'package:aster/features/transaction/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remixicon/remixicon.dart';

void main() {
  testWidgets('quiet pending blocks pointer, keyboard and semantic actions', (
    tester,
  ) async {
    var pending = false;
    var calls = 0;
    late StateSetter rebuild;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return QuietPendingAction(
            pending: pending,
            label: 'Continue',
            child: CustomButton(
              text: 'Continue',
              hapticIntent: null,
              onTap: () => calls += 1,
            ),
          );
        },
      ),
    );
    final button = find.widgetWithText(CustomButton, 'Continue');
    final before = tester.getRect(button);
    await tester.tap(button);
    expect(calls, 1);
    await tester.pumpAndSettle();

    rebuild(() => pending = true);
    await tester.pumpAndSettle();
    expect(tester.getRect(button), before);
    expect(tester.widget<CustomButton>(button).loading, isFalse);
    expect(find.byType(GridLoader), findsNothing);
    _expectUnavailable(tester, 'Continue');
    await tester.tap(button, warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);

    rebuild(() => pending = false);
    await tester.pump();
    final semantics = tester.getSemantics(find.bySemanticsLabel('Continue'));
    expect(
      semantics.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      true,
    );
    await tester.tap(button);
    expect(calls, 2);
  });

  testWidgets('Paste retains its label, geometry and colour during the read', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var pasting = false;
    var calls = 0;
    late StateSetter rebuild;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return SendAddressCard(
            target: WalletPaymentTarget.bitcoinOnchain,
            controller: controller,
            enabled: !pasting,
            pasting: pasting,
            onChanged: (_) {},
            onClear: () {},
            onPaste: () => calls += 1,
            onSubmitted: () {},
          );
        },
      ),
    );
    final button = find.widgetWithText(CustomButton, 'Paste');
    final before = tester.getRect(button);
    rebuild(() => pasting = true);
    await tester.pumpAndSettle();
    expect(tester.getRect(button), before);
    expect(tester.widget<CustomButton>(button).enabled, true);
    expect(tester.widget<CustomButton>(button).loading, false);
    expect(find.byType(GridLoader), findsNothing);
    _expectUnavailable(tester, 'Paste');
    await tester.tap(button, warnIfMissed: false);
    expect(calls, 0);
    rebuild(() => pasting = false);
    await tester.pump();
    await tester.tap(button);
    expect(calls, 1);
  });

  testWidgets(
    'transaction copy keeps the copy icon during all pending writes',
    (tester) async {
      var copying = false;
      var calls = 0;
      late StateSetter rebuild;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return TransactionDetailRow(
              label: 'Transaction ID',
              value: 'a' * 64,
              identifier: true,
              copying: copying,
              copyEnabled: !copying,
              onCopy: () => calls += 1,
            );
          },
        ),
      );
      final icon = find.byIcon(RemixIcons.file_copy_line);
      final before = tester.getRect(icon);
      rebuild(() => copying = true);
      await tester.pump();
      expect(icon, findsOneWidget);
      expect(tester.getRect(icon), before);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      _expectUnavailable(tester, 'Copy Transaction ID');
      await tester.tap(icon, warnIfMissed: false);
      expect(calls, 0);
      rebuild(() => copying = false);
      await tester.pump();
      await tester.tap(icon);
      expect(calls, 1);
    },
  );

  testWidgets('send success Continue stays visible during navigation', (
    tester,
  ) async {
    var continuing = false;
    var calls = 0;
    late StateSetter rebuild;
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return SendSuccessView(
            result: WalletSendResult(
              route: route,
              amount: WalletAmount.onchain(
                assetId: WalletAsset.bitcoin.id,
                units: 100,
              ),
              status: WalletPaymentStatus.pending,
              referenceId: 'a' * 64,
            ),
            bitcoinUnit: BitcoinUnit.bitcoin,
            continuing: continuing,
            onContinue: () => calls += 1,
          );
        },
      ),
    );
    final button = find.widgetWithText(CustomButton, 'Continue');
    final before = tester.getRect(button);
    rebuild(() => continuing = true);
    await tester.pump();
    expect(tester.getRect(button), before);
    expect(tester.widget<CustomButton>(button).loading, false);
    expect(tester.widget<CustomButton>(button).enabled, true);
    expect(find.byType(GridLoader), findsNothing);
    _expectUnavailable(tester, 'Continue');
    await tester.tap(button, warnIfMissed: false);
    expect(calls, 0);
    rebuild(() => continuing = false);
    await tester.pump();
    await tester.tap(button);
    expect(calls, 1);
  });

  for (final link in [
    SettingsExternalLink.termsOfService,
    SettingsExternalLink.privacyPolicy,
  ]) {
    testWidgets('${link.name} keeps both rows unchanged during handoff', (
      tester,
    ) async {
      SettingsExternalLink? opening;
      final calls = <SettingsExternalLink>[];
      late StateSetter rebuild;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return SettingsLinksCard(
              loading: false,
              state: SettingsAppState(
                availableLinks: {
                  SettingsExternalLink.termsOfService,
                  SettingsExternalLink.privacyPolicy,
                },
                openingLink: opening,
              ),
              onOpen: calls.add,
            );
          },
        ),
      );
      final rows = find.byType(AsterOptionRow);
      final before = [
        for (final row in rows.evaluate())
          tester.getRect(find.byWidget(row.widget)),
      ];
      rebuild(() => opening = link);
      await tester.pump();
      expect(find.text('Opening'), findsNothing);
      expect(find.byIcon(RemixIcons.arrow_right_s_line), findsNWidgets(2));
      expect([
        for (final row in rows.evaluate())
          tester.getRect(find.byWidget(row.widget)),
      ], before);
      for (final label in ['Terms of Service', 'Privacy Policy']) {
        _expectUnavailable(tester, label);
        await tester.tap(find.text(label), warnIfMissed: false);
      }
      expect(calls, isEmpty);
      rebuild(() => opening = null);
      await tester.pump();
      await tester.tap(find.text('Terms of Service'));
      expect(calls, [SettingsExternalLink.termsOfService]);
    });
  }
}

void _expectUnavailable(WidgetTester tester, String label) {
  final node = tester.getSemantics(find.bySemanticsLabel(label));
  expect(node.flagsCollection.isEnabled, ui.Tristate.isFalse);
  expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), false);
  expect(node.getSemanticsData().value, isEmpty);
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  ),
);

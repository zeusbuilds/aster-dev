import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/models/models.dart';
import 'package:aster/features/receive/presentation/screens/screens.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shareFailure = AppFailure(
    code: 'share_unavailable',
    kind: AppFailureKind.unavailable,
    userMessage: 'Sharing is unavailable on this device.',
    retryable: false,
  );

  for (final target in [
    WalletPaymentTarget.bitcoinOnchain,
    WalletPaymentTarget.usdtOnchain,
  ]) {
    for (final (outcome, result) in <(String, AppResult<ShareDisposition>)>[
      ('completed', const AppResult.success(ShareDisposition.completed)),
      ('dismissed', const AppResult.success(ShareDisposition.dismissed)),
      ('failed', const AppResult.failure(shareFailure)),
    ]) {
      testWidgets(
        '${target.name} share stays visually steady while $outcome sheet is pending',
        (tester) async {
          final engine = FakeWalletEngine();
          if (target == WalletPaymentTarget.usdtOnchain) {
            engine.createdReceiveRequest = WalletReceiveRequest(
              route: testRgbRoute,
              encodedRequest: 'rgb:synthetic-receive-presentation-fixture',
              displayValue: 'rgb:synthetic-receive-presentation-fixture',
            );
          }
          final harness = await PaymentFlowTestHarness.create(
            engine: engine,
            services: testRgbServices,
          );
          final share = _HeldShareService();
          final container = ProviderContainer(
            retry: (_, _) => null,
            overrides: [
              walletRepositoryProvider.overrideWith(
                (ref) async => harness.repository,
              ),
              settingsRepositoryProvider.overrideWith(
                (ref) =>
                    harness.container.read(settingsRepositoryProvider.future),
              ),
              hapticFeedbackServiceProvider.overrideWithValue(harness.haptics),
              clipboardServiceProvider.overrideWithValue(harness.clipboard),
              shareServiceProvider.overrideWithValue(share),
            ],
          );
          addTearDown(() async {
            if (!share.completion.isCompleted) {
              share.completion.complete(
                const AppResult.success(ShareDisposition.dismissed),
              );
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            container.dispose();
            final disposal = harness.dispose();
            for (var frame = 0; frame < 3; frame += 1) {
              await tester.pump();
            }
            await disposal;
          });
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 1000);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.light(),
                home: AsterFeedbackScope(
                  haptics: harness.haptics,
                  toasts: harness.toasts,
                  child: ReceiveRequestScreen(target: target),
                ),
              ),
            ),
          );
          final provider = receiveFlowViewModelProvider(target);
          await _pumpUntil(tester, () => container.read(provider).hasValue);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Share'));
          await tester.pumpAndSettle();

          final initial = container.read(provider).requireValue;
          final engineCalls = List<String>.of(engine.calls);
          final baseline = _requestPresentation(tester);
          final shareAction = _row(tester, 'Share').onTap!;
          final copyAction = tester
              .widget<CustomButton>(find.widgetWithText(CustomButton, 'Copy'))
              .onTap!;
          final regenerateAction = _row(tester, 'Generate new request').onTap!;
          final amountAction = _row(tester, 'Set amount').onTap!;
          // Exercise callbacks from the initiating frame as well as input
          // after rebuilding: a platform sheet need not appear immediately.
          shareAction();
          shareAction();
          copyAction();
          regenerateAction();
          amountAction();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));

          expect(share.calls, 1);
          expect(
            share.subject,
            '${initial.route.asset.displayName} payment request',
          );
          expect(share.text, initial.request!.encodedRequest);
          expect(share.origin?.isValid, isTrue);
          expect(
            container.read(provider).requireValue.operation,
            ReceiveFlowOperation.sharingRequest,
          );
          expect(_requestPresentation(tester), baseline);
          expect(find.text('Opening'), findsNothing);
          expect(find.byType(ReceiveAmountSheet), findsNothing);
          expect(find.text('Use blind receive'), findsNothing);
          expect(find.text('Witness receive'), findsNothing);
          expect(harness.clipboard.text, isNull);
          expect(engine.calls, engineCalls);
          expect(harness.toasts.messages, isEmpty);
          expect(harness.haptics.intents, isEmpty);

          for (final title in ['Share', 'Set amount', 'Generate new request']) {
            final row = find.widgetWithText(AsterOptionRow, title);
            expect(
              tester
                  .getSemantics(row)
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            await tester.tap(row, warnIfMissed: false);
          }
          // The authoritative ViewModel lock also rejects direct commands.
          final notifier = container.read(provider.notifier);
          expect(
            await notifier.shareRequest(),
            isA<AppFailureResult<ShareDisposition>>(),
          );
          expect(await notifier.copyRequest(), isA<AppFailureResult<void>>());
          expect(await notifier.regenerate(), isFalse);
          notifier.updateAmount('1');
          await tester.pump();
          expect(share.calls, 1);
          expect(engine.calls, engineCalls);
          expect(container.read(provider).requireValue.amountText, '');
          expect(harness.toasts.messages, isEmpty);
          expect(harness.haptics.intents, isEmpty);

          share.completion.complete(result);
          await tester.pumpAndSettle();
          expect(container.read(provider).requireValue, initial);
          expect(_requestPresentation(tester), baseline);
          if (outcome == 'failed') {
            expect(harness.toasts.messages, hasLength(1));
            expect(
              harness.toasts.messages.single.title,
              'Could not share request',
            );
            expect(
              harness.toasts.messages.single.message,
              shareFailure.userMessage,
            );
            expect(harness.haptics.intents, [HapticIntent.error]);
          } else {
            expect(harness.toasts.messages, isEmpty);
            expect(harness.haptics.intents, isEmpty);
          }
          expect(
            tester
                .getSemantics(find.widgetWithText(AsterOptionRow, 'Share'))
                .getSemanticsData()
                .hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          copyAction();
          await tester.pumpAndSettle();
          expect(harness.clipboard.text, initial.request!.encodedRequest);
          expect(harness.toasts.messages.last.title, 'Payment request copied');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

AsterOptionRow _row(WidgetTester tester, String title) =>
    tester.widget<AsterOptionRow>(find.widgetWithText(AsterOptionRow, title));

Object _requestPresentation(WidgetTester tester) {
  final copy = find.widgetWithText(CustomButton, 'Copy');
  return <String, Object?>{
    'rows': [
      for (final title in ['Set amount', 'Generate new request', 'Share'])
        <String, Object?>{
          'bounds': tester.getRect(find.widgetWithText(AsterOptionRow, title)),
          'enabled': _row(tester, title).onTap != null,
          'details': _row(tester, title).details,
          'icons': [
            for (final icon in tester.widgetList<Icon>(
              find.descendant(
                of: find.widgetWithText(AsterOptionRow, title),
                matching: find.byType(Icon),
              ),
            ))
              (icon.icon, icon.color, icon.size),
          ],
        },
    ],
    'copyBounds': tester.getRect(copy),
    'copyEnabled': tester.widget<CustomButton>(copy).enabled,
    'copyLoading': tester.widget<CustomButton>(copy).loading,
    'copyOpacity': tester
        .widget<Opacity>(
          find.descendant(of: copy, matching: find.byType(Opacity)),
        )
        .opacity,
  };
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 200; frame += 1) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for receive request.');
}

final class _HeldShareService implements ShareService {
  final completion = Completer<AppResult<ShareDisposition>>();
  var calls = 0;
  String? text;
  String? subject;
  ShareOrigin? origin;

  @override
  Future<AppResult<ShareDisposition>> shareText(
    String value, {
    String? subject,
    ShareOrigin? origin,
  }) {
    calls += 1;
    text = value;
    this.subject = subject;
    this.origin = origin;
    return completion.future;
  }
}

import 'package:aster/features/swap/presentation/models/models.dart';
import 'package:aster/features/swap/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/presentation_fakes.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'DM Sans',
    )..addFont(rootBundle.load('assets/fonts/DMSans-Variable.ttf'))).load();
  });

  testWidgets('Swap circles remain separate and reverse stays on the divider', (
    tester,
  ) async {
    final capabilities = [
      WalletPaymentCapability.available(
        const PaymentRoute(
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.onchain,
        ),
      ),
      WalletPaymentCapability.available(
        PaymentRoute(
          asset: WalletAsset.rgbUsdt(assetId: 'configured-usdt', precision: 6),
          rail: PaymentRail.onchain,
        ),
      ),
    ];
    final state = SwapState(
      capabilities: capabilities,
      from: WalletPaymentTarget.bitcoinOnchain,
      to: WalletPaymentTarget.usdtOnchain,
    );
    var reverseCount = 0;
    var sawUnequalPairHeights = false;
    for (final width in [280.0, 320.0, 390.0]) {
      for (final textScale in [1.0, 1.5, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: AsterFeedbackScope(
                haptics: RecordingHapticFeedbackService(),
                toasts: RecordingToastPresentationService(),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: SizedBox(
                      width: width,
                      child: SwapCard(
                        state: state,
                        onSelectFrom: () {},
                        onSelectTo: () {},
                        onReverse: () => reverseCount += 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final pairs = find.byType(SwapPair);
        final topPair = tester.getRect(pairs.at(0));
        final bottomPair = tester.getRect(pairs.at(1));
        final cardRect = tester.getRect(find.byType(SwapCard));
        final subtle = tester.element(pairs.at(1)).appColors.surfaceSubtle;
        final lowerControlBand = find.descendant(
          of: find.byType(SwapCard),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ColoredBox &&
                widget.child == null &&
                widget.color == subtle,
          ),
        );
        final lowerBandRect = tester.getRect(lowerControlBand);
        expect(lowerBandRect.left, cardRect.left);
        expect(lowerBandRect.right, cardRect.right);
        expect(lowerBandRect.bottom, bottomPair.top);
        sawUnequalPairHeights |= topPair.height != bottomPair.height;
        final reverse = find.byTooltip('Reverse swap direction');
        final control = tester.getRect(reverse);
        final divider = tester.getRect(find.byType(AsterDivider));
        final topAsset = tester.getRect(
          find.descendant(
            of: pairs.at(0),
            matching: find.byType(WalletAssetIcon),
          ),
        );
        final bottomAsset = tester.getRect(
          find.descendant(
            of: pairs.at(1),
            matching: find.byType(WalletAssetIcon),
          ),
        );
        expect(control.size, const Size(48, 48));
        expect(control.center.dy, divider.center.dy);
        expect(control.top - topAsset.bottom, greaterThanOrEqualTo(8));
        expect(bottomAsset.top - control.bottom, greaterThanOrEqualTo(8));
        if (width == 390 && textScale == 1) {
          // Normal-size rows have exactly 8px clearance plus half the 1px
          // divider; wrapping can only increase clearance around the icons.
          expect(control.top - topAsset.bottom, closeTo(8.5, 0.001));
          expect(bottomAsset.top - control.bottom, closeTo(8.5, 0.001));
          expect(cardRect.height, 185);
        }
        expect(topAsset.top - topPair.top, greaterThanOrEqualTo(24));
        expect(
          bottomPair.bottom - bottomAsset.bottom,
          greaterThanOrEqualTo(24),
        );
        // Both halves of the reserved control remain tappable, rather than
        // falling outside a parent Stack's hit region.
        final previousReversals = reverseCount;
        await tester.tapAt(control.topCenter + const Offset(0, 4));
        await tester.tapAt(control.bottomCenter - const Offset(0, 4));
        expect(reverseCount, previousReversals + 2);
        expect(tester.takeException(), isNull);
      }
    }
    expect(sawUnequalPairHeights, isTrue);
  });
}

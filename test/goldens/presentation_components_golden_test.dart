import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('DM Sans', 'assets/fonts/DMSans-Variable.ttf');
    await _loadFont('Public Sans', 'assets/fonts/PublicSans-Variable.ttf');
    await _loadFont(
      'packages/ming_cute_icons/MingCute',
      'packages/ming_cute_icons/lib/fonts/MingCute.ttf',
    );
  });

  testWidgets('shared presentation components match the approved system', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const _PresentationGoldenHarness());
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('presentation-golden')),
      matchesGoldenFile('presentation_components.png'),
    );
  });

  testWidgets('shared controls meet labeled touch-target and contrast rules', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const _PresentationGoldenHarness());
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}

Future<void> _loadFont(String family, String asset) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(asset));
  await loader.load();
}

class _PresentationGoldenHarness extends StatelessWidget {
  const _PresentationGoldenHarness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        );
      },
      home: AsterFeedbackScope(
        haptics: const NoopHapticFeedbackService(),
        toasts: const _NoopToasts(),
        child: Scaffold(
          body: SafeArea(
            child: RepaintBoundary(
              key: const ValueKey('presentation-golden'),
              child: ColoredBox(
                color: AppTheme.light().colorScheme.surface,
                child: Builder(
                  builder: (context) {
                    final spacing = context.spacing;
                    return Padding(
                      padding: EdgeInsets.all(spacing.screenPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Wallet controls', style: context.type.title),
                          SizedBox(height: spacing.lg),
                          CustomButton(text: 'Continue', onTap: _noop),
                          SizedBox(height: spacing.md),
                          CustomButton(
                            text: 'Review transaction',
                            variant: ButtonVariant.secondary,
                            onTap: _noop,
                          ),
                          SizedBox(height: spacing.md),
                          const CustomButton(
                            text: 'Creating wallet',
                            loading: true,
                          ),
                          SizedBox(height: spacing.xl),
                          Squircle(
                            padding: EdgeInsets.all(spacing.lg),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Available',
                                        style: context.type.rowMeta,
                                      ),
                                      SizedBox(height: spacing.xs),
                                      const AmountText(r'$1,234.50 BTC'),
                                    ],
                                  ),
                                ),
                                AsterPill(
                                  color: context.colorScheme.primaryContainer,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: spacing.md,
                                    vertical: spacing.xs,
                                  ),
                                  child: Text(
                                    'Onchain',
                                    style: context.type.badgeLabel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: spacing.md),
                          Row(
                            children: [
                              const AsterSelectionIndicator(selected: true),
                              SizedBox(width: spacing.sm),
                              Text(
                                'Selected wallet',
                                style: context.type.rowTitle,
                              ),
                            ],
                          ),
                          const Spacer(),
                          CustomToast(
                            title: 'Address copied',
                            message: 'Ready to paste in another wallet.',
                            variant: ToastVariant.success,
                            onDismiss: _noop,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _noop() {}

final class _NoopToasts implements ToastPresentationService {
  const _NoopToasts();

  @override
  void dismissCurrent({int? id}) {}

  @override
  bool show({
    required String title,
    required ToastVariant variant,
    String? message,
    Duration? duration,
  }) {
    return true;
  }
}

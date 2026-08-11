import 'dart:ui' as ui;

import 'package:aster/features/skeleton/presentation/widgets/bottom_nav.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('theme extensions fail fast outside an Aster theme root', (
    tester,
  ) async {
    const probeKey = ValueKey('probe');
    await tester.pumpWidget(const MaterialApp(home: SizedBox(key: probeKey)));

    final context = tester.element(find.byKey(probeKey));
    expect(() => context.spacing, throwsFlutterError);
  });

  testWidgets('window insets preserve safe, system, and keyboard spaces', (
    tester,
  ) async {
    late AsterWindowInsets observed;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 20),
            viewPadding: EdgeInsets.only(top: 20, bottom: 34),
            viewInsets: EdgeInsets.only(bottom: 300),
          ),
          child: Builder(
            builder: (context) {
              observed = context.windowInsets;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(observed.topSafe, 20);
    expect(observed.bottomSafe, 0);
    expect(observed.bottomSystem, 34);
    expect(observed.keyboard, 300);
    expect(observed.keyboardVisible, isTrue);
  });

  testWidgets('amount text applies Public Sans only to numeric spans', (
    tester,
  ) async {
    late List<TextSpan> spans;
    await tester.pumpWidget(
      _themedHarness(
        Builder(
          builder: (context) {
            spans = NumericTextSpans.build(
              context,
              r'$1,234.50 BTC',
              context.type.rowValue,
            );
            return const AmountText(r'$1,234.50 BTC');
          },
        ),
      ),
    );

    expect(spans.map((span) => span.text), [r'$', '1,234.50', ' BTC']);
    expect(spans.map((span) => span.style?.fontFamily), [
      'DM Sans',
      'Public Sans',
      'DM Sans',
    ]);
  });

  test('theme assigns exact squircle and capsule shape types', () {
    final theme = AppTheme.light();
    expect(theme.cardTheme.shape, isA<RoundedSuperellipseBorder>());
    expect(theme.dialogTheme.shape, isA<RoundedSuperellipseBorder>());
    expect(theme.bottomSheetTheme.shape, isA<RoundedSuperellipseBorder>());
    expect(theme.snackBarTheme.shape, isA<RoundedSuperellipseBorder>());
    final input = theme.inputDecorationTheme.border;
    expect(input, isA<ShapedInputBorder>());
    expect(
      (input! as ShapedInputBorder).shape,
      isA<RoundedSuperellipseBorder>(),
    );
  });

  testWidgets('buttons suppress haptics while disabled or loading', (
    tester,
  ) async {
    final haptics = _RecordingHaptics();
    var activations = 0;

    await tester.pumpWidget(
      _themedHarness(
        CustomButton(
          text: 'Continue',
          onTap: () => activations += 1,
          hapticIntent: HapticIntent.commit,
        ),
        haptics: haptics,
      ),
    );
    expect(tester.getSize(find.byType(CustomButton)).height, 48);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Continue'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(find.byType(CustomButton));
    await tester.pump();
    expect(activations, 1);
    expect(haptics.intents, [HapticIntent.commit]);

    await tester.pumpWidget(
      _themedHarness(
        CustomButton(
          text: 'Continue',
          loading: true,
          onTap: () => activations += 1,
        ),
        haptics: haptics,
      ),
    );
    await tester.tap(find.byType(CustomButton));
    await tester.pump();
    expect(activations, 1);
    expect(haptics.intents, [HapticIntent.commit]);
    expect(find.bySemanticsLabel('Continue'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Continue'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
  });

  testWidgets('button activation is keyboard operable', (tester) async {
    final haptics = _RecordingHaptics();
    var activations = 0;
    await tester.pumpWidget(
      _themedHarness(
        CustomButton(text: 'Continue', onTap: () => activations += 1),
        haptics: haptics,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(activations, 1);
    expect(haptics.intents, [HapticIntent.lightImpact]);
  });

  testWidgets('reduced motion leaves loaders settled', (tester) async {
    await tester.pumpWidget(
      _themedHarness(const GridLoader(), disableAnimations: true),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation indicator stays centered on each slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AsterFeedbackScope(
            haptics: const NoopHapticFeedbackService(),
            toasts: _NoopToasts(),
            child: const Scaffold(body: Stack(children: [BottomNav()])),
          ),
        ),
      ),
    );

    final indicator = find.byKey(const ValueKey('bottom-nav-indicator'));
    final home = find.byKey(const ValueKey('bottom-nav-home'));
    final scan = find.byKey(const ValueKey('bottom-nav-scan'));
    expect(
      tester.getCenter(indicator).dx,
      closeTo(tester.getCenter(home).dx, 0.1),
    );

    await tester.tap(scan);
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(indicator).dx,
      closeTo(tester.getCenter(scan).dx, 0.1),
    );
  });

  testWidgets('toast host announces, dismisses, and advances its queue', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hapticFeedbackServiceProvider.overrideWithValue(
            NoopHapticFeedbackService(),
          ),
        ],
        child: const _ToastHarness(),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('First'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Information. First. Details'),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Dismiss'));
    await tester.pump();
    expect(find.text('Second'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 101));
    await tester.pump();
    expect(find.text('Second'), findsNothing);
  });
}

Widget _themedHarness(
  Widget child, {
  HapticFeedbackService haptics = const NoopHapticFeedbackService(),
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: AsterFeedbackScope(
        haptics: haptics,
        toasts: _NoopToasts(),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

final class _RecordingHaptics implements HapticFeedbackService {
  final intents = <HapticIntent>[];

  @override
  Future<void> trigger(HapticIntent intent) {
    intents.add(intent);
    return Future<void>.value();
  }
}

final class _NoopToasts implements ToastPresentationService {
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

class _ToastHarness extends ConsumerWidget {
  const _ToastHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(toastControllerProvider.notifier);
    final haptics = ref.watch(hapticFeedbackServiceProvider);
    return MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: AsterFeedbackScope(
            haptics: haptics,
            toasts: controller,
            child: ToastHost(child: child!),
          ),
        );
      },
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: TextButton(
                onPressed: () {
                  context.toasts
                    ..show(
                      title: 'First',
                      message: 'Details',
                      variant: ToastVariant.info,
                      duration: const Duration(milliseconds: 100),
                    )
                    ..show(
                      title: 'Second',
                      variant: ToastVariant.warning,
                      duration: const Duration(milliseconds: 100),
                    );
                },
                child: const Text('Show'),
              ),
            );
          },
        ),
      ),
    );
  }
}

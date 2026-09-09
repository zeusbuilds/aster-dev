import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/features/shell/presentation/providers/providers.dart';
import 'package:aster/features/shell/presentation/widgets/bottom_nav.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remixicon/remixicon.dart';

import '../support/presentation_fakes.dart';

void main() {
  testWidgets('toast has Material text styling outside the route navigator', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => CustomToast(
          title: 'Copied',
          message: 'Address copied',
          variant: ToastVariant.success,
          onDismiss: () {},
        ),
        home: const SizedBox.shrink(),
      ),
    );
    final text = tester.element(find.text('Address copied'));
    expect(DefaultTextStyle.of(text).style.decoration, TextDecoration.none);
    expect(
      find.ancestor(
        of: find.text('Address copied'),
        matching: find.byType(Material),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'option rows reflow long values instead of clipping at large text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: AsterOptionRow(
                    title: 'Wallet details',
                    details: 'Unavailable',
                    prefixIcon: Icons.info_outline,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final title = tester.getRect(find.text('Wallet details'));
      final value = tester.getRect(find.text('Unavailable'));
      expect(value.top, greaterThanOrEqualTo(title.bottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('theme extensions fail fast outside an Aster theme root', (
    tester,
  ) async {
    const probeKey = ValueKey('probe');
    await tester.pumpWidget(const MaterialApp(home: SizedBox(key: probeKey)));

    final context = tester.element(find.byKey(probeKey));
    expect(() => context.spacing, throwsFlutterError);
  });

  testWidgets('status messages own one intentional semantics announcement', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themedHarness(
        const Column(
          children: [
            AsterStatusMessage(
              'Payment failed safely.',
              tone: AsterStatusTone.danger,
              announce: true,
            ),
            AsterStatusMessage(
              'Enter a valid amount.',
              tone: AsterStatusTone.danger,
            ),
          ],
        ),
      ),
    );

    final operationFailure = find.bySemanticsLabel('Payment failed safely.');
    final validation = find.bySemanticsLabel('Enter a valid amount.');
    expect(operationFailure, findsOneWidget);
    expect(validation, findsOneWidget);
    expect(
      tester.getSemantics(operationFailure).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(
      tester.getSemantics(validation).flagsCollection.isLiveRegion,
      isFalse,
    );
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

  testWidgets('numeric spans preserve localized digits and separators', (
    tester,
  ) async {
    late List<TextSpan> arabicSpans;
    late List<TextSpan> indicSpans;
    await tester.pumpWidget(
      _themedHarness(
        Builder(
          builder: (context) {
            arabicSpans = NumericTextSpans.build(
              context,
              'د.إ −١٬٢٣٤٫٥٠ BTC',
              context.type.rowValue,
            );
            indicSpans = NumericTextSpans.build(
              context,
              '₹१२ ३४५.६७ INR',
              context.type.rowValue,
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(arabicSpans.map((span) => span.text), ['د.إ ', '−١٬٢٣٤٫٥٠', ' BTC']);
    expect(arabicSpans.map((span) => span.style?.fontFamily), [
      'DM Sans',
      'Public Sans',
      'DM Sans',
    ]);
    expect(indicSpans.map((span) => span.text), ['₹', '१२ ३४५.६७', ' INR']);
    expect(indicSpans.map((span) => span.style?.fontFamily), [
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

  test('light theme has stable identity across root rebuilds', () {
    expect(identical(AppTheme.light(), AppTheme.light()), isTrue);
  });

  test('neutral status typography preserves the Material body contract', () {
    final theme = AppTheme.light();
    final roles = theme.extension<AsterTypeRoles>()!;

    expect(roles.statusMessage.fontFamily, 'DM Sans');
    expect(roles.statusMessage.fontSize, theme.textTheme.bodyMedium!.fontSize);
    expect(roles.statusMessage.fontWeight, FontWeight.w400);
    expect(roles.statusMessage.color, theme.colorScheme.onSurface);
  });

  test(
    'typography families switch discretely at the interpolation midpoint',
    () {
      const source = AsterTypography(
        fontFamilyPrimary: 'Primary A',
        fontFamilyNumeric: 'Numeric A',
      );
      const destination = AsterTypography(
        fontFamilyPrimary: 'Primary B',
        fontFamilyNumeric: 'Numeric B',
      );

      expect(source.lerp(destination, 0.49), same(source));
      expect(source.lerp(destination, 0.5), same(destination));
      expect(source.lerp(null, 1), same(source));
    },
  );

  testWidgets('detail rows classify fee rates as numeric metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themedHarness(const DetailRow(title: 'Fee rate', value: '7 sats/vbyte')),
    );

    expect(find.byType(NumericText), findsOneWidget);
    expect(find.byType(AmountText), findsNothing);
  });

  testWidgets('squircle resolves its default border from the active theme', (
    tester,
  ) async {
    final baseTheme = AppTheme.light();
    final theme = baseTheme.copyWith(
      extensions: [
        ...baseTheme.extensions.values.where((value) => value is! AsterStrokes),
        const AsterStrokes(border: 2.5),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Squircle(child: SizedBox.square(dimension: 8)),
        ),
      ),
    );

    final decoratedBox = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(Squircle),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.position == DecorationPosition.foreground,
        ),
      ),
    );
    final decoration = decoratedBox.decoration as ShapeDecoration;
    final shape = decoration.shape as RoundedSuperellipseBorder;
    expect(shape.side.width, 2.5);
    expect(find.byType(ClipRSuperellipse), findsOneWidget);
  });

  testWidgets('compact pills retain width while loading and full hit height', (
    tester,
  ) async {
    var activations = 0;
    final haptics = _RecordingHaptics();
    Widget button({bool loading = false}) => _themedHarness(
      Center(
        child: CustomButton.compact(
          text: 'Copy address',
          loading: loading,
          onTap: () => activations++,
        ),
      ),
      haptics: haptics,
    );
    await tester.pumpWidget(button());
    final finder = find.byType(CustomButton);
    final before = tester.getRect(finder);
    expect(before.height, 48);
    expect(before.width, lessThan(250));
    await tester.tapAt(Offset(before.center.dx, before.top + 1));
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(activations, 2);
    expect(haptics.intents, hasLength(2));
    await tester.pumpWidget(button(loading: true));
    await tester.pump();
    expect(tester.getRect(finder), before);
    await tester.tapAt(Offset(before.center.dx, before.top + 1));
    expect(activations, 2);
    expect(haptics.intents, hasLength(2));
  });

  testWidgets('option values and chevrons share a stable trailing edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themedHarness(
        Column(
          children: [
            AsterOptionRow(title: 'Currency', details: 'USD', onTap: () {}),
            AsterOptionRow(
              title: 'Region',
              details: 'United States',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    final rows = find.byType(AsterOptionRow);
    final icons = [
      for (var i = 0; i < 2; i++)
        tester.getRect(
          find.descendant(of: rows.at(i), matching: find.byType(Icon)),
        ),
    ];
    expect(icons[0].right, icons[1].right);
    expect(tester.getRect(rows.first).right - icons[0].right, 20);
  });

  testWidgets('selection indicator is decorative and token-sized', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themedHarness(const AsterSelectionIndicator(selected: true)),
    );

    expect(
      tester.getSize(find.byType(AsterSelectionIndicator)),
      const Size.square(16),
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AsterSelectionIndicator),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
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

  testWidgets('button releases pressed scale when disabled during a gesture', (
    tester,
  ) async {
    var loading = false;
    var activations = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _themedHarness(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return CustomButton(
              text: 'Continue',
              loading: loading,
              onTap: () => activations += 1,
            );
          },
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomButton)),
    );
    await tester.pump();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      const AsterMotion().buttonPressedScale,
    );

    rebuild(() => loading = true);
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);

    await gesture.up();
    await tester.pump();
    expect(activations, 0);
  });

  testWidgets('icon buttons own enabled and loading semantic actions', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      _themedHarness(
        AsterIconButton(
          icon: Icons.copy,
          tooltip: 'Copy value',
          onPressed: () => activations += 1,
        ),
      ),
    );

    final enabled = tester
        .getSemantics(find.bySemanticsLabel('Copy value'))
        .getSemanticsData();
    expect(enabled.hasAction(ui.SemanticsAction.tap), isTrue);
    await tester.tap(find.bySemanticsLabel('Copy value'));
    expect(activations, 1);

    await tester.pumpWidget(
      _themedHarness(
        AsterIconButton(
          icon: Icons.copy,
          tooltip: 'Copy value',
          loading: true,
          onPressed: () => activations += 1,
        ),
      ),
    );

    final loading = tester
        .getSemantics(find.bySemanticsLabel('Copy value'))
        .getSemanticsData();
    expect(loading.hasAction(ui.SemanticsAction.tap), isFalse);
    expect(loading.value, 'Loading');
  });

  testWidgets('option rows expose affordance and haptic only when enabled', (
    tester,
  ) async {
    final haptics = _RecordingHaptics();
    var activations = 0;
    await tester.pumpWidget(
      _themedHarness(
        AsterOptionRow(
          title: 'Configured action',
          onTap: () => activations += 1,
        ),
        haptics: haptics,
      ),
    );

    expect(find.byIcon(RemixIcons.arrow_right_s_line), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Configured action'))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(find.bySemanticsLabel('Configured action'));
    expect(activations, 1);
    expect(haptics.intents, [HapticIntent.lightImpact]);

    await tester.pumpWidget(
      _themedHarness(
        const AsterOptionRow(
          title: 'Unavailable action',
          details: 'Unavailable',
        ),
        haptics: haptics,
      ),
    );
    expect(find.byIcon(RemixIcons.arrow_right_s_line), findsNothing);
    expect(
      tester
          .getSemantics(
            find.bySemanticsLabel('Unavailable action, Unavailable'),
          )
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    await tester.tap(find.text('Unavailable action'));
    expect(activations, 1);
    expect(haptics.intents, [HapticIntent.lightImpact]);
  });

  testWidgets(
    'screen navigation owner suppresses same-frame sibling commands',
    (tester) async {
      final gate = Completer<void>();
      final haptics = _RecordingHaptics();
      final accepted = <String>[];
      await tester.pumpWidget(
        _themedHarness(
          _NavigationHarness(
            first: () async {
              accepted.add('first');
              await gate.future;
            },
            second: () async => accepted.add('second'),
          ),
          haptics: haptics,
        ),
      );

      final first = tester.widget<CustomButton>(
        find.widgetWithText(CustomButton, 'First'),
      );
      final second = tester.widget<CustomButton>(
        find.widgetWithText(CustomButton, 'Second'),
      );
      first.onTap!();
      second.onTap!();
      await tester.pump();

      expect(accepted, ['first']);
      expect(haptics.intents, [HapticIntent.lightImpact]);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('First'))
            .flagsCollection
            .isEnabled,
        ui.Tristate.isFalse,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Second'))
            .flagsCollection
            .isEnabled,
        ui.Tristate.isFalse,
      );

      gate.complete();
      await tester.pump();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Second'))
            .flagsCollection
            .isEnabled,
        ui.Tristate.isTrue,
      );
    },
  );

  testWidgets(
    'durable command blocks same-frame system pop until ownership releases',
    (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: _PopGuardRoot(gate: gate),
        ),
      );

      await tester.tap(find.text('Open guarded route'));
      await tester.pumpAndSettle();
      expect(find.text('Guarded route'), findsOneWidget);

      final mutate = tester.widget<CustomButton>(
        find.widgetWithText(CustomButton, 'Start mutation'),
      );
      mutate.onTap!();
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Guarded route'), findsOneWidget);
      expect(find.text('Root route'), findsNothing);

      gate.complete();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Guarded route'), findsNothing);
      expect(find.text('Root route'), findsOneWidget);
    },
  );

  testWidgets('reduced motion leaves loaders settled', (tester) async {
    await tester.pumpWidget(
      _themedHarness(const GridLoader(), disableAnimations: true),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone loaders announce progress and embedded ones do not', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themedHarness(const GridLoader(semanticLabel: 'Loading wallet details')),
    );
    expect(find.bySemanticsLabel('Loading wallet details'), findsOneWidget);

    await tester.pumpWidget(_themedHarness(const GridLoader()));
    expect(find.bySemanticsLabel('Loading wallet details'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(GridLoader),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });

  testWidgets('generic loaders default to a surface-visible theme color', (
    tester,
  ) async {
    await tester.pumpWidget(_themedHarness(const GridLoader()));

    final loader = tester.widget<GridLoader>(find.byType(GridLoader));
    expect(loader.colorStyle, GridLoaderColorStyle.themePrimary);
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

  testWidgets(
    'selected navigation remains enabled without duplicate feedback',
    (tester) async {
      final haptics = RecordingHapticFeedbackService();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AsterFeedbackScope(
              haptics: haptics,
              toasts: _NoopToasts(),
              child: const Scaffold(body: Stack(children: [BottomNav()])),
            ),
          ),
        ),
      );

      final home = find.byKey(const ValueKey('bottom-nav-home'));
      final scan = find.byKey(const ValueKey('bottom-nav-scan'));
      final selected = tester.getSemantics(home).getSemanticsData();
      expect(selected.flagsCollection.isSelected, ui.Tristate.isTrue);
      expect(selected.flagsCollection.isEnabled, ui.Tristate.isTrue);
      expect(selected.hasAction(ui.SemanticsAction.tap), isTrue);

      await tester.tap(home);
      await tester.pump();
      expect(haptics.intents, isEmpty);

      await tester.tap(scan);
      await tester.pumpAndSettle();
      expect(haptics.intents, [HapticIntent.selection]);
    },
  );

  test('app-shell selection rejects impossible destination indices', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen<int>(
      appShellIndexProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    final notifier = container.read(appShellIndexProvider.notifier);

    notifier.setIndex(appShellTabCount - 1);
    expect(container.read(appShellIndexProvider), appShellTabCount - 1);

    expect(() => notifier.setIndex(-1), throwsRangeError);
    expect(() => notifier.setIndex(appShellTabCount), throwsRangeError);
    expect(container.read(appShellIndexProvider), appShellTabCount - 1);
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

  testWidgets('toast visibility time pauses while the app is inactive', (
    tester,
  ) async {
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
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
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('First'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('First'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 59));
    expect(find.text('First'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2));
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('UXA-015 accessible toast queue requires explicit dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: _ToastHarness(accessibleNavigation: true)),
    );
    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Dismiss'));
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Second'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Dismiss'));
    await tester.pump();
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('UXA-015 accessibility setting changes preserve remaining time', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _ToastHarness()));
    await tester.tap(find.text('Show'));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(
      const ProviderScope(child: _ToastHarness(accessibleNavigation: true)),
    );
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('First'), findsOneWidget);
    await tester.pumpWidget(const ProviderScope(child: _ToastHarness()));
    await tester.pump(const Duration(milliseconds: 59));
    expect(find.text('First'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2));
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('UXA-015 focused dismissal pauses countdown while reading', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _ToastHarness()));
    await tester.tap(find.text('Show'));
    await tester.pump();
    final dismissIcon = find.descendant(
      of: find.byType(AsterIconButton),
      matching: find.byType(Icon),
    );
    Focus.of(tester.element(dismissIcon)).requestFocus();
    await tester.pump();
    expect(Focus.of(tester.element(find.byType(CustomToast))).hasFocus, isTrue);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('First'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 101));
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('UXA-015 Escape dismisses a toast from the focused route', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: _ToastHarness(accessibleNavigation: true)),
    );
    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets(
    'UXA-015 assistive focus latches visibility without stealing focus',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: _ToastHarness()));
      await tester.tap(find.text('Show'));
      await tester.pump();
      final node = tester.getSemantics(
        find.bySemanticsLabel('Information. First. Details'),
      );
      node.owner!.performAction(
        node.id,
        ui.SemanticsAction.didGainAccessibilityFocus,
      );
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('First'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Dismiss'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 101));
      await tester.pump();
      expect(find.text('Second'), findsNothing);
    },
  );
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

final class _NavigationHarness extends StatelessWidget {
  const _NavigationHarness({required this.first, required this.second});

  final Future<void> Function() first;
  final Future<void> Function() second;

  @override
  Widget build(BuildContext context) {
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);

          void run(Future<void> Function() command) {
            unawaited(
              navigation.run(
                command: command,
                failureTitle: 'Page could not open',
              ),
            );
          }

          return Row(
            children: [
              Expanded(
                child: CustomButton(
                  text: 'First',
                  enabled: !navigation.inFlight,
                  hapticIntent: null,
                  onTap: () => run(first),
                ),
              ),
              SizedBox(width: context.spacing.sm),
              Expanded(
                child: CustomButton(
                  text: 'Second',
                  enabled: !navigation.inFlight,
                  hapticIntent: null,
                  onTap: () => run(second),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _PopGuardRoot extends StatelessWidget {
  const _PopGuardRoot({required this.gate});

  final Completer<void> gate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Root route'),
          TextButton(
            onPressed: () {
              unawaited(
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => _PopGuardRoute(gate: gate),
                  ),
                ),
              );
            },
            child: const Text('Open guarded route'),
          ),
        ],
      ),
    );
  }
}

final class _PopGuardRoute extends StatelessWidget {
  const _PopGuardRoute({required this.gate});

  final Completer<void> gate;

  @override
  Widget build(BuildContext context) {
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          return Scaffold(
            body: Column(
              children: [
                const Text('Guarded route'),
                CustomButton(
                  text: 'Start mutation',
                  enabled: !navigation.inFlight,
                  hapticIntent: null,
                  onTap: () {
                    unawaited(
                      navigation.run(
                        command: () => gate.future,
                        failureTitle: 'Mutation failed',
                        hapticIntent: null,
                        blocksRoutePop: true,
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ToastHarness extends ConsumerWidget {
  const _ToastHarness({this.accessibleNavigation = false});

  final bool accessibleNavigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(toastControllerProvider.notifier);
    final haptics = ref.watch(hapticFeedbackServiceProvider);
    return MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            accessibleNavigation: accessibleNavigation,
          ),
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

import 'dart:ui' as ui;

import 'package:aster/shared/shared.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all themed state layers suppress pressed ink but retain focus', () {
    final theme = AppTheme.light();
    expect(theme.splashFactory, NoSplash.splashFactory);
    expect(theme.splashColor.a, 0);
    expect(theme.highlightColor.a, 0);
    expect(theme.focusColor.a, greaterThan(0));
    expect(theme.hoverColor.a, greaterThan(0));
    final overlays = <WidgetStateProperty<Color?>>[
      theme.elevatedButtonTheme.style!.overlayColor!,
      theme.filledButtonTheme.style!.overlayColor!,
      theme.outlinedButtonTheme.style!.overlayColor!,
      theme.textButtonTheme.style!.overlayColor!,
      theme.iconButtonTheme.style!.overlayColor!,
      theme.switchTheme.overlayColor!,
      theme.checkboxTheme.overlayColor!,
      theme.radioTheme.overlayColor!,
      theme.tabBarTheme.overlayColor!,
      theme.navigationBarTheme.overlayColor!,
      theme.sliderTheme.overlayColor! as WidgetStateColor,
    ];
    for (final overlay in overlays) {
      expect(overlay.resolve({WidgetState.pressed})!.a, 0);
      expect(
        overlay.resolve({WidgetState.pressed, WidgetState.selected})!.a,
        0,
      );
      expect(
        overlay.resolve({WidgetState.disabled, WidgetState.focused})!.a,
        0,
      );
      expect(overlay.resolve({WidgetState.focused})!.a, greaterThan(0));
      expect(overlay.resolve({WidgetState.hovered})!.a, greaterThan(0));
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('${platform.name} held taps paint no ripple or highlight', (
      tester,
    ) async {
      const boundaryKey = ValueKey('tap-policy-pixels');
      var calls = 0;
      void activate() => calls++;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: platform),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              // Ink paints on its nearest Material, which must be captured too.
              child: Material(
                child: Column(
                  children: [
                    InkWell(
                      key: const ValueKey('row'),
                      onTap: activate,
                      child: const SizedBox(
                        width: 120,
                        height: 48,
                        child: Center(child: Text('Row')),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('icon'),
                      onPressed: activate,
                      icon: const Icon(Icons.copy),
                    ),
                    TextButton(
                      key: const ValueKey('text'),
                      onPressed: activate,
                      child: const Text('Text'),
                    ),
                    ElevatedButton(
                      key: const ValueKey('elevated'),
                      onPressed: activate,
                      child: const Text('Elevated'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('outlined'),
                      onPressed: activate,
                      child: const Text('Outlined'),
                    ),
                    FilledButton(
                      key: const ValueKey('filled'),
                      onPressed: activate,
                      child: const Text('Filled'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in [
        'row',
        'icon',
        'text',
        'elevated',
        'outlined',
        'filled',
      ]) {
        final before = await _pixels(tester, boundaryKey);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(ValueKey(key))),
        );
        await tester.pump(const Duration(milliseconds: 150));
        // The first frame can start ink after the tap-recognition deadline.
        // Advance its animation too, so a zero-alpha first frame cannot pass.
        await tester.pump(const Duration(milliseconds: 150));
        expect(
          await _pixels(tester, boundaryKey),
          before,
          reason: '$key painted pressed ink',
        );
        await gesture.up();
        await tester.pumpAndSettle();
      }
      expect(calls, 6);
    });
  }

  testWidgets('pixel harness detects default Material ink', (tester) async {
    const boundaryKey = ValueKey('default-ink-pixels');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: Material(
              child: InkWell(
                onTap: () {},
                child: const SizedBox(width: 120, height: 48),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = await _pixels(tester, boundaryKey);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(InkWell)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
    expect(await _pixels(tester, boundaryKey), isNot(before));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'custom button keeps its scale response without a pressed overlay',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: CustomButton(
              text: 'Continue',
              onTap: () {},
              hapticIntent: null,
            ),
          ),
        ),
      );
      final ink = tester.widget<InkWell>(find.byType(InkWell));
      expect(ink.overlayColor!.resolve({WidgetState.pressed})!.a, 0);
      expect(
        ink.overlayColor!.resolve({WidgetState.focused})!.a,
        greaterThan(0),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CustomButton)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        lessThan(1),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    },
  );
}

Future<String> _pixels(WidgetTester tester, Key key) async {
  final digest = await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return sha256.convert(bytes!.buffer.asUint8List()).toString();
    } finally {
      image.dispose();
    }
  });
  return digest!;
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/backdrop_text_contrast.dart';

void main() {
  for (final scenario in [
    (name: 'dark gradient passes', bright: false, alpha: 1.0, pass: true),
    (name: 'bright patch fails', bright: true, alpha: 1.0, pass: false),
    (name: 'translucent text fails', bright: false, alpha: 0.2, pass: false),
  ]) {
    testWidgets(scenario.name, (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    key: const ValueKey('backdrop'),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black,
                            scenario.bright ? Colors.white : Colors.indigo,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      'Contrast',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: scenario.alpha),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final result = await BackdropTextContrastGuideline(
        backdrop: find.byKey(const ValueKey('backdrop')),
        labels: const {'Contrast'},
        underlay: Colors.black,
      ).evaluate(tester);
      expect(result.passed, scenario.pass, reason: result.reason);
    });
  }

  testWidgets('unlisted labels still receive the standard contrast check', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ColoredBox(
          color: Colors.white,
          child: Center(
            child: Text('Unlisted', style: TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
    final result = await BackdropTextContrastGuideline(
      backdrop: find.byKey(const ValueKey('not-present')),
      labels: const {'Contrast'},
      underlay: Colors.black,
    ).evaluate(tester);
    expect(result.passed, isFalse);
  });
}

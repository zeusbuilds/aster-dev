import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aster/shared/shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('light color tokens expose the semantic brand contract', () {
    const colors = AsterColors.light;

    expect(AsterColors.blueBase, const Color(0xFF165DFF));
    expect(AsterColors.ink, const Color(0xFF1D2129));
    expect(AsterColors.meshMain, const Color(0xFF001AFF));
    expect(AsterColors.meshSoft, const Color(0xFF8BD0FF));
    expect(colors.surfaceRaised, AsterColors.white);
    expect(colors.chartPositive, colors.success);
    expect(colors.chartNegative, colors.danger);
    expect(colors.homeGradient, hasLength(5));
  });

  test('core token decisions stay intentionally compact', () {
    const spacing = AsterSpacing();
    const radii = AsterRadii();

    expect(spacing.screenPadding, 20);
    expect(spacing.sectionGap, 24);
    expect(spacing.controlGap, 12);

    expect(radii.card, 24);
    expect(radii.input, 12);
    expect(radii.pill, 999);
  });
}

import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('light color tokens expose the semantic brand contract', () {
    final scheme = AsterColors.lightColorScheme();
    const colors = AsterColors.light;
    const gradients = AsterGradients.light;

    expect(scheme.primary, const Color(0xFF165DFF));
    expect(scheme.onSurface, const Color(0xFF1D2129));
    expect(colors.brandArtMain, const Color(0xFF001AFF));
    expect(colors.brandArtSoft, const Color(0xFF8BD0FF));
    expect(colors.surfaceRaised, scheme.surface);
    expect(colors.chartPositive, colors.success);
    expect(colors.chartNegative, colors.danger);
    expect(gradients.splashBackdrop.colors, hasLength(3));
  });

  test('core token decisions stay intentionally compact', () {
    const spacing = AsterSpacing();
    const radii = AsterRadii();
    const icons = AsterIconography();
    const metrics = AsterComponentMetrics();

    expect(spacing.screenPadding, 20);
    expect(spacing.sectionGap, 24);
    expect(spacing.controlGap, 12);

    expect(radii.card, 24);
    expect(radii.input, 12);

    expect(icons.xxs, 12);
    expect(icons.md, 24);
    expect(metrics.minTouchTarget, 48);
    expect(metrics.flagSize, 32);
    expect(metrics.selectionIndicatorWidth, 4);
  });
}

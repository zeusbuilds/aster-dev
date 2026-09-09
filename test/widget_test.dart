import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('light color tokens expose the semantic brand contract', () {
    final scheme = AsterColors.lightColorScheme();
    const colors = AsterColors.light;
    final gradients = AsterGradients.light;

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
    const art = AsterArt();
    const stateLayers = AsterStateLayers();

    expect(spacing.screenPadding, 20);
    expect(spacing.sectionGap, 24);
    expect(spacing.md, 12);

    expect(radii.card, 24);
    expect(radii.sheet, 28);
    expect(radii.button, 18);
    expect(radii.input, 12);
    expect(radii.badge, 8);
    expect(radii.checkbox, 4);
    expect(radii.snackbar, 12);
    expect(radii.floatingActionButton, 16);

    expect(icons.xxs, 12);
    expect(icons.md, 24);
    expect(metrics.minTouchTarget, 48);
    expect(metrics.flagSize, 32);
    expect(metrics.selectionIndicatorSize, 16);
    expect(metrics.paymentTargetTileMinHeight, 80);
    expect(metrics.appBarHeight, 64);
    expect(metrics.qrLogoSizeFactor, 0.16);
    expect(radii.recoveryWord, 24);
    expect(radii.keypad, 18);
    expect(art.onboardingIconTileRadius, 4);
    expect(stateLayers.visible, 1);
    expect(stateLayers.hidden, 0);
  });

  test(
    'shadow tokens own immutable lists and preserve interpolation entries',
    () {
      final source = <BoxShadow>[
        const BoxShadow(color: Colors.black, blurRadius: 4),
      ];
      final shadows = AsterShadows(raised: source);

      source.clear();
      expect(shadows.raised, hasLength(1));
      expect(() => shadows.raised.clear(), throwsUnsupportedError);

      final destination = AsterShadows(
        raised: const [
          BoxShadow(color: Colors.white, blurRadius: 8),
          BoxShadow(color: Colors.blue, blurRadius: 12),
        ],
      );
      expect(shadows.lerp(destination, 0.5).raised, hasLength(2));
    },
  );

  test(
    'gradient tokens own immutable lists and preserve interpolation entries',
    () {
      final sourceColors = <Color>[Colors.black, Colors.grey];
      final sourceStops = <double>[0, 1];
      final gradient = AsterGradientSpec(
        colors: sourceColors,
        stops: sourceStops,
      );

      sourceColors.clear();
      sourceStops.clear();
      expect(gradient.colors, const [Colors.black, Colors.grey]);
      expect(gradient.stops, const [0, 1]);
      expect(() => gradient.colors.clear(), throwsUnsupportedError);
      expect(() => gradient.stops!.clear(), throwsUnsupportedError);
      expect(
        () => AsterGradientSpec(colors: const [Colors.black]),
        throwsArgumentError,
      );
      expect(
        () => AsterGradientSpec(
          colors: const [Colors.black, Colors.white],
          stops: const [0],
        ),
        throwsArgumentError,
      );
      expect(
        () => AsterGradientSpec(
          colors: const [Colors.black, Colors.white],
          stops: const [0.8, 0.2],
        ),
        throwsArgumentError,
      );
      expect(
        () => AsterGradientSpec(
          colors: const [Colors.black, Colors.white],
          stops: const [0, double.nan],
        ),
        throwsArgumentError,
      );

      final destination = AsterGradientSpec(
        colors: const [Colors.white, Colors.blue, Colors.red],
        stops: const [0, 0.25, 1],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      );
      final midpoint = gradient.lerp(destination, 0.5);

      expect(midpoint.colors, hasLength(3));
      expect(midpoint.stops, const [0, 0.25, 1]);
      expect(midpoint.begin, const Alignment(-1, 0));
      expect(midpoint.end, const Alignment(1, 0));
    },
  );
}

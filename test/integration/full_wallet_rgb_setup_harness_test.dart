import 'dart:async';

import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/full_wallet_rgb_setup.dart';

enum _PreparationPhase { waiting, disabled, enabled, ready }

void main() {
  testWidgets(
    'ready native status can precede the rendered Check preparation control',
    (tester) async {
      final phase = ValueNotifier(_PreparationPhase.waiting);
      addTearDown(phase.dispose);
      final timers = <Timer>[];
      addTearDown(() {
        for (final timer in timers) {
          timer.cancel();
        }
      });
      var checks = 0;
      var financialDispatches = 0;
      var witnessSelections = 0;
      await _pumpPreparation(
        tester,
        phase,
        onCheck: () {
          checks += 1;
          timers.add(
            Timer(const Duration(milliseconds: 350), () {
              phase.value = _PreparationPhase.ready;
            }),
          );
        },
        onConfirm: () => financialDispatches += 1,
        onWitness: () => witnessSelections += 1,
      );
      expect(
        find.widgetWithText(CustomButton, 'Check preparation'),
        findsNothing,
      );
      timers.add(
        Timer(const Duration(milliseconds: 150), () {
          phase.value = _PreparationPhase.enabled;
        }),
      );

      await qualifyPreparedBlindReceiveUi(
        tester,
        isBlindRequestReady: () => phase.value == _PreparationPhase.ready,
        timeout: const Duration(seconds: 2),
      );

      expect(checks, 1);
      expect(financialDispatches, 0);
      expect(witnessSelections, 0);
      expect(phase.value, _PreparationPhase.ready);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'visible disabled preparation waits until enabled and checks only once',
    (tester) async {
      final phase = ValueNotifier(_PreparationPhase.disabled);
      addTearDown(phase.dispose);
      final timers = <Timer>[];
      addTearDown(() {
        for (final timer in timers) {
          timer.cancel();
        }
      });
      var checks = 0;
      var financialDispatches = 0;
      var witnessSelections = 0;
      await _pumpPreparation(
        tester,
        phase,
        onCheck: () {
          checks += 1;
          // Keep the button enabled until completion to prove the helper does
          // not dispatch a second check on subsequent frames.
          timers.add(
            Timer(const Duration(milliseconds: 450), () {
              phase.value = _PreparationPhase.ready;
            }),
          );
        },
        onConfirm: () => financialDispatches += 1,
        onWitness: () => witnessSelections += 1,
      );
      final check = find.widgetWithText(CustomButton, 'Check preparation');
      expect(check.hitTestable(), findsOneWidget);
      expect(tester.widget<CustomButton>(check).enabled, isFalse);
      expect(tester.widget<CustomButton>(check).loading, isTrue);
      timers.add(
        Timer(const Duration(milliseconds: 150), () {
          phase.value = _PreparationPhase.enabled;
        }),
      );

      await qualifyPreparedBlindReceiveUi(
        tester,
        isBlindRequestReady: () => phase.value == _PreparationPhase.ready,
        timeout: const Duration(seconds: 2),
      );

      expect(checks, 1);
      expect(financialDispatches, 0);
      expect(witnessSelections, 0);
      expect(phase.value, _PreparationPhase.ready);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'an already settled Blind request requires no new check or financial action',
    (tester) async {
      final phase = ValueNotifier(_PreparationPhase.ready);
      addTearDown(phase.dispose);
      var checks = 0;
      var financialDispatches = 0;
      var witnessSelections = 0;
      await _pumpPreparation(
        tester,
        phase,
        onCheck: () => checks += 1,
        onConfirm: () => financialDispatches += 1,
        onWitness: () => witnessSelections += 1,
      );

      await qualifyPreparedBlindReceiveUi(
        tester,
        isBlindRequestReady: () => phase.value == _PreparationPhase.ready,
      );

      expect(checks, 0);
      expect(financialDispatches, 0);
      expect(witnessSelections, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _pumpPreparation(
  WidgetTester tester,
  ValueNotifier<_PreparationPhase> phase, {
  required VoidCallback onCheck,
  required VoidCallback onConfirm,
  required VoidCallback onWitness,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: ValueListenableBuilder<_PreparationPhase>(
        valueListenable: phase,
        builder: (context, value, _) => Column(
          children: [
            if (value != _PreparationPhase.waiting &&
                value != _PreparationPhase.ready)
              CustomButton(
                text: 'Check preparation',
                enabled: value == _PreparationPhase.enabled,
                loading: value == _PreparationPhase.disabled,
                onTap: onCheck,
              ),
            // These controls are available throughout. Checking an existing
            // preparation must never re-confirm it or select Witness instead.
            CustomButton(text: 'Confirm setup', onTap: onConfirm),
            CustomButton(text: 'Use witness receive', onTap: onWitness),
          ],
        ),
      ),
    ),
  ),
);

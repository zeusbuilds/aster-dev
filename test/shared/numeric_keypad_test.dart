import 'dart:ui' as ui;

import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

void main() {
  testWidgets('keypad edits exact decimal text with stable controls', (
    tester,
  ) async {
    var value = '';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: AsterFeedbackScope(
              haptics: const NoopHapticFeedbackService(),
              toasts: ToastController(),
              child: AsterNumericKeypad(
                value: value,
                allowDecimal: true,
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('.'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(value, '1.2');
    await tester.tap(find.byIcon(MingCuteIcons.mgc_delete_back_line));
    await tester.pump();
    expect(value, '1.');
    await tester.longPress(find.byIcon(MingCuteIcons.mgc_delete_back_line));
    await tester.pump();
    expect(value, isEmpty);
  });

  testWidgets('integer keypad disables decimal input', (tester) async {
    var value = '1';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AsterFeedbackScope(
            haptics: const NoopHapticFeedbackService(),
            toasts: ToastController(),
            child: AsterNumericKeypad(
              value: value,
              allowDecimal: false,
              onChanged: (next) => value = next,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('.'));
    expect(value, '1');
  });

  testWidgets('keypad exposes actions only when they can edit the value', (
    tester,
  ) async {
    var value = '';
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(
              body: AsterFeedbackScope(
                haptics: const NoopHapticFeedbackService(),
                toasts: ToastController(),
                child: AsterNumericKeypad(
                  value: value,
                  allowDecimal: true,
                  maximumCharacters: 2,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            );
          },
        ),
      ),
    );

    bool hasAction(String label, ui.SemanticsAction action) => tester
        .getSemantics(find.bySemanticsLabel(label))
        .getSemanticsData()
        .hasAction(action);

    expect(hasAction('Delete digit', ui.SemanticsAction.tap), isFalse);
    expect(hasAction('Delete digit', ui.SemanticsAction.longPress), isFalse);
    expect(hasAction('.', ui.SemanticsAction.tap), isTrue);

    await tester.tap(find.text('0'));
    await tester.pump();
    expect(value, '0');
    expect(hasAction('0', ui.SemanticsAction.tap), isFalse);
    expect(hasAction('1', ui.SemanticsAction.tap), isTrue);
    expect(hasAction('Delete digit', ui.SemanticsAction.longPress), isTrue);

    await tester.tap(find.text('.'));
    await tester.pump();
    expect(value, '0.');
    expect(hasAction('.', ui.SemanticsAction.tap), isFalse);
    expect(hasAction('1', ui.SemanticsAction.tap), isFalse);

    rebuild(() => value = '12');
    await tester.pump();
    for (final digit in const [
      '0',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
    ]) {
      expect(hasAction(digit, ui.SemanticsAction.tap), isFalse);
    }
    expect(hasAction('.', ui.SemanticsAction.tap), isFalse);
    expect(hasAction('Delete digit', ui.SemanticsAction.tap), isTrue);
  });
}

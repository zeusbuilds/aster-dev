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
}

import 'package:aster/core/bootstrap/app_loader.dart';
import 'package:aster/core/errors/errors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows redacted bootstrap failure and can recover on retry', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      AppLoader(
        initialize: () async {
          attempts += 1;
          if (attempts == 1) {
            throw const AppFailureException(
              AppFailure(
                code: 'test_bootstrap_failure',
                kind: AppFailureKind.storage,
                userMessage: 'Wallet data could not be opened safely.',
                retryable: true,
              ),
            );
          }
          return ProviderContainer();
        },
        child: const MaterialApp(home: Text('Ready')),
      ),
    );
    await tester.pump();

    expect(find.text('Wallet could not be opened'), findsOneWidget);
    expect(
      find.text('Wallet data could not be opened safely.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Wallet could not be opened'), findsNothing);
  });

  testWidgets('does not offer retry when startup outcome is unknown', (
    tester,
  ) async {
    await tester.pumpWidget(
      AppLoader(
        initialize: () async {
          throw const AppFailureException(
            AppFailure(
              code: 'test_bootstrap_outcome_unknown',
              kind: AppFailureKind.storage,
              userMessage: 'Restart the app before continuing.',
              retryable: false,
              outcomeUnknown: true,
            ),
          );
        },
        child: const MaterialApp(home: Text('Ready')),
      ),
    );
    await tester.pump();

    expect(find.text('Restart the app before continuing.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}

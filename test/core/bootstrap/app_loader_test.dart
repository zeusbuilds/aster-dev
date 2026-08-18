import 'dart:async';

import 'package:aster/core/bootstrap/app_loader.dart';
import 'package:aster/core/errors/errors.dart';
import 'package:aster/shared/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('startup splash owns semantics until the app is revealed', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final initialization = Completer<ProviderContainer>();
    await tester.pumpWidget(
      AppLoader(
        initialize: () => initialization.future,
        child: const MaterialApp(home: Text('Ready')),
      ),
    );

    expect(find.bySemanticsLabel('Opening UTEXO'), findsOneWidget);
    expect(find.bySemanticsLabel('Ready'), findsNothing);

    initialization.complete(ProviderContainer());
    await tester.pump();
    await tester.pump();

    expect(find.text('Ready'), findsOneWidget);
    expect(find.bySemanticsLabel('Opening UTEXO'), findsOneWidget);
    expect(find.bySemanticsLabel('Ready'), findsNothing);

    const motion = AsterMotion();
    await tester.pump(motion.bootstrapRevealDelay);
    await tester.pump();
    await tester.pumpAndSettle(motion.splashRevealDuration);
    expect(find.bySemanticsLabel('Opening UTEXO'), findsNothing);
    expect(find.bySemanticsLabel('Ready'), findsOneWidget);
    semantics.dispose();
  });

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
    final failure = find.bySemanticsLabel(
      'Wallet data could not be opened safely.',
    );
    expect(failure, findsOneWidget);
    expect(tester.getSemantics(failure).flagsCollection.isLiveRegion, isTrue);
    final failureContext = tester.element(
      find.text('Wallet could not be opened'),
    );
    final surface = Theme.of(failureContext).colorScheme.surface;
    final systemStyles = tester
        .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        )
        .map((region) => region.value);
    expect(
      systemStyles,
      contains(
        isA<SystemUiOverlayStyle>()
            .having(
              (style) => style.systemNavigationBarColor,
              'navigation bar color',
              surface,
            )
            .having(
              (style) => style.systemNavigationBarIconBrightness,
              'navigation icon brightness',
              Brightness.dark,
            )
            .having(
              (style) => style.statusBarIconBrightness,
              'status icon brightness',
              Brightness.dark,
            ),
      ),
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

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/core.dart';
import 'package:aster/features/settings/data/repository/repository.dart';
import 'package:aster/features/settings/domain/models/models.dart';
import 'package:aster/features/settings/presentation/models/models.dart';
import 'package:aster/features/settings/presentation/screens/screens.dart';
import 'package:aster/features/settings/presentation/view_model/view_models.dart';
import 'package:aster/features/settings/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/payment_flow_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bitcoin unit commits before closing and remains accessible', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = SettingsRepository(
      PreferencesService(await SharedPreferences.getInstance()),
      _CatalogAssetBundle(),
    );
    final haptics = _RecordingHaptics();
    final toasts = _RecordingToasts();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/unit'),
                child: const Text('Open unit settings'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/unit',
          builder: (context, state) => const BitcoinUnitSelectionScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => AsterFeedbackScope(
            haptics: haptics,
            toasts: toasts,
            child: child!,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open unit settings'));
    await tester.pumpAndSettle();

    expect(find.text('Satoshis'), findsOneWidget);
    final selected = tester
        .getSemantics(find.bySemanticsLabel(RegExp(r'^Bitcoin,')))
        .getSemanticsData();
    final unselected = tester
        .getSemantics(find.bySemanticsLabel(RegExp(r'^Satoshis,')))
        .getSemanticsData();
    expect(selected.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(selected.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(selected.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(selected.hasAction(ui.SemanticsAction.tap), isFalse);
    expect(unselected.flagsCollection.isSelected, ui.Tristate.isFalse);
    expect(unselected.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(unselected.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));

    await tester.tap(find.text('Satoshis'));
    await tester.pumpAndSettle();

    expect(find.text('Open unit settings'), findsOneWidget);
    final persisted = await repository.load() as AppSuccess<SettingsSnapshot>;
    expect(persisted.value.preferences.bitcoinUnit, BitcoinUnit.sats);
    expect(haptics.intents, [HapticIntent.selection]);
    expect(toasts.messages, isEmpty);
  });

  testWidgets('choice loading exposes status without fabricated options', (
    tester,
  ) async {
    await _pumpPendingSelection(
      tester,
      screen: const CurrencySelectionScreen(),
    );
    expect(find.bySemanticsLabel('Loading currencies'), findsOneWidget);
    expect(find.bySemanticsLabel('Loading currency'), findsNothing);

    await _pumpPendingSelection(tester, screen: const CountrySelectionScreen());
    expect(find.bySemanticsLabel('Loading regions'), findsOneWidget);
    expect(find.bySemanticsLabel('Loading region'), findsNothing);
  });

  testWidgets('app-information loading has one live semantic owner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SettingsLinksCard(state: null, loading: true, onOpen: (_) {}),
        ),
      ),
    );

    final loading = find.bySemanticsLabel('Loading app information');
    expect(loading, findsOneWidget);
    expect(tester.getSemantics(loading).flagsCollection.isLiveRegion, isTrue);
    expect(find.bySemanticsLabel(RegExp('Contact Support')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Privacy Policy')), findsNothing);
  });

  testWidgets('settings preference loading is a live non-fabricated status', (
    tester,
  ) async {
    final pending = Completer<SettingsState>();
    await _pumpSettingsScreen(
      tester,
      walletFuture: Future.value(WalletState(activeWallet: _walletProfile)),
      appRepository: _appRepository(),
      settingsViewModelFactory: () => _PendingSettingsViewModel(pending.future),
    );
    await tester.pump();

    final loading = find.bySemanticsLabel('Loading app settings');
    expect(loading, findsOneWidget);
    expect(tester.getSemantics(loading).flagsCollection.isLiveRegion, isTrue);
    expect(find.bySemanticsLabel(RegExp('Currency,')), findsNothing);
  });

  for (final screen in const [
    CountrySelectionScreen(),
    CurrencySelectionScreen(),
    BitcoinUnitSelectionScreen(),
  ]) {
    testWidgets('${screen.runtimeType} scrolls through the bottom safe area', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 932);
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsViewModelProvider.overrideWith(
              () => _StaticSettingsViewModel(_selectionState),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: screen),
        ),
      );
      await tester.pumpAndSettle();

      final list = find.byType(ListView);
      expect(tester.getBottomLeft(list).dy, 932);
      final padding = tester
          .widget<ListView>(list)
          .padding!
          .resolve(TextDirection.ltr);
      expect(padding.bottom, 34 + tester.element(list).spacing.lg);
      expect(tester.takeException(), isNull);
    });
  }

  for (final retryable in [true, false]) {
    for (final scenario in const [
      (name: 'currency', screen: CurrencySelectionScreen()),
      (name: 'region', screen: CountrySelectionScreen()),
      (name: 'Bitcoin unit', screen: BitcoinUnitSelectionScreen()),
    ]) {
      testWidgets(
        '${scenario.name} load ${retryable ? 'shows' : 'hides'} retry',
        (tester) async {
          final failure = AppFailure(
            code: retryable
                ? 'settings_temporarily_unavailable'
                : 'settings_configuration_invalid',
            kind: retryable
                ? AppFailureKind.unavailable
                : AppFailureKind.configuration,
            userMessage: retryable
                ? 'Settings are temporarily unavailable.'
                : 'Settings are not configured.',
            retryable: retryable,
          );
          await tester.pumpWidget(
            ProviderScope(
              retry: applicationProviderRetryPolicy,
              overrides: [
                settingsViewModelProvider.overrideWith(
                  () => _FailingSettingsViewModel(failure),
                ),
              ],
              child: MaterialApp(
                theme: AppTheme.light(),
                home: scenario.screen,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text(failure.userMessage), findsOneWidget);
          expect(find.text('Retry'), retryable ? findsOneWidget : findsNothing);
        },
      );
    }
  }

  testWidgets('all choice screens honor a foreign preference save', (
    tester,
  ) async {
    final state = SettingsState(
      snapshot: SettingsSnapshot(
        preferences: AppPreferences.defaults,
        currencies: [
          FiatCurrency(
            name: 'United States Dollar',
            symbol: r'$',
            code: 'USD',
            countryCode: 'US',
          ),
        ],
        regions: [Region(name: 'United States', code: 'US')],
      ),
      operation: SettingsOperation.balanceVisibility,
    );
    final scenarios = <({Widget screen, Finder option})>[
      (
        screen: const CurrencySelectionScreen(),
        option: find.bySemanticsLabel(r'United States Dollar, $ USD'),
      ),
      (
        screen: const CountrySelectionScreen(),
        option: find.bySemanticsLabel('United States'),
      ),
      (
        screen: const BitcoinUnitSelectionScreen(),
        option: find.bySemanticsLabel(RegExp(r'^Bitcoin,')),
      ),
    ];

    for (final scenario in scenarios) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsViewModelProvider.overrideWith(
              () => _StaticSettingsViewModel(state),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: scenario.screen),
        ),
      );
      await tester.pump();
      await tester.pump();

      final semantics = tester.getSemantics(scenario.option).getSemanticsData();
      expect(semantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
      expect(semantics.hasAction(ui.SemanticsAction.tap), isFalse);
      expect(find.bySemanticsLabel('Saving preference'), findsOneWidget);
      final back = tester
          .getSemantics(find.bySemanticsLabel('Back'))
          .getSemanticsData();
      expect(back.flagsCollection.isEnabled, ui.Tristate.isFalse);
      expect(back.hasAction(ui.SemanticsAction.tap), isFalse);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(scenario.option, findsOneWidget);
    }
  });

  for (final scenario in const [
    (name: 'currency', screen: CurrencySelectionScreen()),
    (name: 'region', screen: CountrySelectionScreen()),
    (name: 'Bitcoin unit', screen: BitcoinUnitSelectionScreen()),
  ]) {
    testWidgets('${scenario.name} save blocks same-frame Back and system pop', (
      tester,
    ) async {
      final viewModel = _ControlledSettingsViewModel(_selectionState);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Text('Settings root'),
          ),
          GoRoute(
            path: '/choice',
            builder: (context, state) => scenario.screen,
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsViewModelProvider.overrideWith(() => viewModel)],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
            builder: (context, child) => AsterFeedbackScope(
              haptics: _RecordingHaptics(),
              toasts: _RecordingToasts(),
              child: child!,
            ),
          ),
        ),
      );
      unawaited(router.push<Object?>('/choice'));
      await tester.pumpAndSettle();

      final back = tester.widget<AsterIconButton>(
        find.byWidgetPredicate(
          (widget) => widget is AsterIconButton && widget.tooltip == 'Back',
        ),
      );
      final navigation = AsterNavigationScope.of(
        tester.element(find.bySemanticsLabel('Back')),
      );
      expect(navigation.inFlight, isFalse);
      expect(router.canPop(), isTrue);
      expect(find.text('Settings root'), findsNothing);
      switch (scenario.name) {
        case 'currency':
          tester
              .widget<CurrencySelectOptionRow>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is CurrencySelectOptionRow &&
                      widget.currency.code == 'EUR',
                ),
              )
              .onTap!();
        case 'region':
          tester
              .widget<CountrySelectOptionRow>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is CountrySelectOptionRow &&
                      widget.country.code == 'DE',
                ),
              )
              .onTap!();
        case 'Bitcoin unit':
          tester
              .widget<SettingsChoiceRow>(
                find.widgetWithText(SettingsChoiceRow, 'Satoshis'),
              )
              .onTap!();
      }
      expect(navigation.inFlight, isTrue);
      expect(router.canPop(), isTrue);
      back.onPressed!();
      expect(router.canPop(), isTrue);
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(router.canPop(), isTrue);
      expect(find.byType(scenario.screen.runtimeType), findsOneWidget);
      expect(find.text('Settings root'), findsNothing);

      viewModel.complete();
      await tester.pump();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Settings root'), findsOneWidget);
      expect(router.canPop(), isFalse);
    });
  }

  testWidgets('region and currency rows expose available choice semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              CountrySelectOptionRow(
                country: Region(name: 'United States', code: 'US'),
                selected: true,
                onTap: () {},
              ),
              CurrencySelectOptionRow(
                currency: FiatCurrency(
                  name: 'United States Dollar',
                  symbol: r'$',
                  code: 'USD',
                  countryCode: 'US',
                ),
                selected: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );

    for (final label in ['United States', r'United States Dollar, $ USD']) {
      final semantics = tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData();
      expect(semantics.flagsCollection.isEnabled, ui.Tristate.isTrue);
      expect(semantics.flagsCollection.isSelected, ui.Tristate.isTrue);
      expect(semantics.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(semantics.hasAction(ui.SemanticsAction.tap), isFalse);
    }
  });

  testWidgets('failed preference save is presented and consumed once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'aster.settings.v1.currency': 'USD',
      'aster.settings.v1.region': 'US',
      'aster.settings.v1.bitcoin_unit': 'btc',
      'aster.settings.v1.balances_visible': true,
    });
    final repository = SettingsRepository(
      _FailingPreferencesService(await SharedPreferences.getInstance()),
      _CatalogAssetBundle(),
    );
    final haptics = _RecordingHaptics();
    final toasts = _RecordingToasts();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: AppTheme.light(),
              home: AsterFeedbackScope(
                haptics: haptics,
                toasts: toasts,
                child: const BitcoinUnitSelectionScreen(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Satoshis'));
    await tester.pumpAndSettle();

    expect(haptics.intents, [HapticIntent.error]);
    expect(toasts.messages, ['Bitcoin unit not saved']);
    expect(
      container.read(settingsViewModelProvider).value?.operationFailure,
      isNull,
    );
  });

  testWidgets('network refresh announces checking without failure prose', (
    tester,
  ) async {
    const configuration = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      indexerUrl: 'http://127.0.0.1:50002/api',
      rgbTransportProxy: 'http://127.0.0.1:3001/json-rpc',
      lspBaseUrl: 'http://127.0.0.1:3100',
      vssUrl: 'http://127.0.0.1:3200',
      explorerBaseUrl: 'https://explorer.example.com/regtest',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkConfigurationViewModelProvider.overrideWith(
            () => _StaticNetworkConfigurationViewModel(
              const NetworkConfigurationState(
                configuration: configuration,
                healthFailure: AppFailure(
                  code: 'health_unavailable',
                  kind: AppFailureKind.unavailable,
                  userMessage: 'Node health is temporarily unavailable.',
                  retryable: true,
                ),
                refreshing: true,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NetworkConfigurationScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final retryButton = find.byWidgetPredicate(
      (widget) => widget is CustomButton && widget.text == 'Retry health check',
    );
    await tester.scrollUntilVisible(retryButton, 300);
    await tester.pump();

    final retry = tester.getSemantics(
      find.bySemanticsLabel('Retry health check'),
    );
    expect(retry.value, 'Loading');
    expect(retry.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Status, Checking'))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(find.text('Node health is temporarily unavailable.'), findsNothing);
    expect(find.text('Details'), findsNothing);
    expect(find.text('Status'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('https://explorer.example.com/regtest'),
      300,
    );
    expect(find.text('http://127.0.0.1:3001/json-rpc'), findsOneWidget);
    expect(find.text('https://explorer.example.com/regtest'), findsOneWidget);
  });

  testWidgets('network health reports node response without inferring peers', (
    tester,
  ) async {
    const configuration = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkConfigurationViewModelProvider.overrideWith(
            () => _StaticNetworkConfigurationViewModel(
              NetworkConfigurationState(
                configuration: configuration,
                status: WalletNetworkStatus(
                  environment: BlockchainEnvironment.regtest,
                  blockHeight: 42,
                  nodePublicKey: _nodePublicKey,
                  channelCount: 0,
                  usableChannelCount: 0,
                  peerCount: 0,
                ),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NetworkConfigurationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Responding'), 300);
    await tester.pump();
    final status = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Status, Responding',
    );
    expect(status, findsOneWidget);
    expect(tester.getSemantics(status).label, 'Status, Responding');
    final peers = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == 'Peers, 0',
    );
    expect(peers, findsOneWidget);
    expect(tester.getSemantics(peers).label, 'Peers, 0');
    expect(find.text('Connected'), findsNothing);
    expect(find.text('Refresh health'), findsOneWidget);
  });

  for (final retryable in [true, false]) {
    testWidgets('network load ${retryable ? 'shows' : 'hides'} retry', (
      tester,
    ) async {
      final failure = AppFailure(
        code: retryable
            ? 'network_temporarily_unavailable'
            : 'network_configuration_invalid',
        kind: retryable
            ? AppFailureKind.unavailable
            : AppFailureKind.configuration,
        userMessage: retryable
            ? 'Network configuration is temporarily unavailable.'
            : 'Network configuration is invalid.',
        retryable: retryable,
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: applicationProviderRetryPolicy,
          overrides: [
            networkConfigurationViewModelProvider.overrideWith(
              () => _FailingNetworkConfigurationViewModel(failure),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const NetworkConfigurationScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(failure.userMessage), findsOneWidget);
      expect(find.text('Retry'), retryable ? findsOneWidget : findsNothing);
    });
  }

  for (final retryable in [true, false]) {
    testWidgets(
      '${retryable ? 'retryable' : 'terminal'} health failure shows only unavailable status quietly',
      (tester) async {
        const configuration = WalletServiceConfiguration(
          environment: BlockchainEnvironment.regtest,
          sdkNetwork: 'regtest',
        );
        final failure = AppFailure(
          code: retryable
              ? 'node_temporarily_unavailable'
              : 'network_configuration_invalid',
          kind: retryable
              ? AppFailureKind.unavailable
              : AppFailureKind.configuration,
          userMessage: retryable
              ? 'Node health is temporarily unavailable.'
              : 'Network configuration is invalid.',
          retryable: retryable,
        );
        final toasts = _RecordingToasts();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              networkConfigurationViewModelProvider.overrideWith(
                () => _StaticNetworkConfigurationViewModel(
                  NetworkConfigurationState(
                    configuration: configuration,
                    healthFailure: failure,
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: AsterFeedbackScope(
                haptics: _RecordingHaptics(),
                toasts: toasts,
                child: const NetworkConfigurationScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Unavailable'), 300);
        await tester.pump();

        expect(find.text('Unavailable'), findsOneWidget);
        expect(find.text(failure.userMessage), findsNothing);
        expect(find.text('Details'), findsNothing);
        expect(find.text('Health check details'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.text('Retry health check'),
          retryable ? findsOneWidget : findsNothing,
        );
        expect(toasts.messages, isEmpty);
      },
    );
  }

  testWidgets('failed explicit health check clears metrics and recovers', (
    tester,
  ) async {
    final harness = await PaymentFlowTestHarness.create();
    final gate = Completer<void>();
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      final disposal = harness.dispose();
      for (var frame = 0; frame < 3; frame += 1) {
        await tester.pump();
      }
      await disposal;
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NetworkConfigurationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Refresh health'), 300);
    expect(find.text('Responding'), findsOneWidget);
    expect(find.text('Block height'), findsOneWidget);
    expect(harness.container.read(toastControllerProvider).current, isNull);

    const failure = AppFailure(
      code: 'node_temporarily_unavailable',
      kind: AppFailureKind.unavailable,
      userMessage: 'Node health is temporarily unavailable.',
      retryable: true,
    );
    harness.engine.networkStatusError = const AppFailureException(failure);
    harness.engine.networkStatusGate = gate;
    await tester.tap(find.text('Refresh health'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Responding'), findsNothing);
    expect(find.text('Block height'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Responding'), findsNothing);
    expect(find.text('Block height'), findsNothing);
    expect(find.text('Channels'), findsNothing);
    expect(find.text('Peers'), findsNothing);
    expect(find.text(failure.userMessage), findsNothing);
    final feedback = harness.container.read(toastControllerProvider);
    expect(feedback.current?.title, 'Health check failed');
    expect(feedback.current?.message, isNull);
    expect(feedback.pending, isEmpty);

    expect(find.text('Details'), findsNothing);
    expect(find.text('Health check details'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    harness.engine.networkStatusError = null;
    harness.engine.networkStatusGate = null;
    await tester.tap(find.text('Retry health check'));
    await tester.pumpAndSettle();
    expect(find.text('Responding'), findsOneWidget);
    expect(find.text('Block height'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
    await tester.scrollUntilVisible(find.text('Refresh health'), 300);
    expect(find.text('Refresh health'), findsOneWidget);
    expect(
      harness.container.read(toastControllerProvider).current?.id,
      feedback.current?.id,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'health failure hides old metrics at large text on narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const failure = AppFailure(
        code: 'health_unavailable',
        kind: AppFailureKind.unavailable,
        userMessage: 'Node health is temporarily unavailable.',
        retryable: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkConfigurationViewModelProvider.overrideWith(
              () => _StaticNetworkConfigurationViewModel(
                NetworkConfigurationState(
                  configuration: const WalletServiceConfiguration(
                    environment: BlockchainEnvironment.regtest,
                    sdkNetwork: 'regtest',
                  ),
                  status: WalletNetworkStatus(
                    environment: BlockchainEnvironment.regtest,
                    blockHeight: 42,
                    nodePublicKey: _nodePublicKey,
                    channelCount: 0,
                    usableChannelCount: 0,
                    peerCount: 0,
                  ),
                  healthFailure: failure,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: const NetworkConfigurationScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Unavailable'), 300);
      expect(find.text('Responding'), findsNothing);
      expect(find.text('Block height'), findsNothing);
      expect(find.text(failure.userMessage), findsNothing);
      final status = tester.getSemantics(
        find.bySemanticsLabel('Status, Unavailable'),
      );
      expect(status.flagsCollection.isLiveRegion, isTrue);
      expect(find.bySemanticsLabel('Details'), findsNothing);
      expect(find.text('Details'), findsNothing);
      expect(find.text('Health check details'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.scrollUntilVisible(find.text('Retry health check'), 300);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'advanced disclosures expose protected actions without placeholder prose',
    (tester) async {
      final haptics = _RecordingHaptics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AsterFeedbackScope(
            haptics: haptics,
            toasts: _RecordingToasts(),
            child: const AdvancedSettingsScreen(),
          ),
        ),
      );

      final exportSemantics = tester.getSemantics(find.text('Export xpubs'));
      final seedSemantics = tester.getSemantics(
        find.text('Reveal seed phrase'),
      );
      expect(exportSemantics.flagsCollection.isEnabled, ui.Tristate.isTrue);
      expect(seedSemantics.flagsCollection.isEnabled, ui.Tristate.isTrue);
      expect(find.text('Unavailable'), findsNothing);
      expect(find.textContaining('authentication policy'), findsNothing);
      expect(haptics.intents, isEmpty);
    },
  );

  testWidgets('Settings owns one navigation command across settings rows', (
    tester,
  ) async {
    final haptics = _RecordingHaptics();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SettingsScreen(),
          routes: [
            GoRoute(
              path: RoutePaths.advancedSettings,
              name: RouteNames.advancedSettings,
              builder: (context, state) => const Text('Advanced destination'),
            ),
            GoRoute(
              path: RoutePaths.bitcoinUnitSelection,
              name: RouteNames.bitcoinUnitSelection,
              builder: (context, state) => const Text('Unit destination'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpSettingsRouter(tester, router: router, haptics: haptics);
    await tester.pumpAndSettle();

    final currency = tester.widget<AsterOptionRow>(
      find.widgetWithText(AsterOptionRow, 'Currency'),
    );
    final unit = tester.widget<AsterOptionRow>(
      find.widgetWithText(AsterOptionRow, 'Bitcoin unit'),
    );
    final advanced = tester.widget<AsterOptionRow>(
      find.widgetWithText(AsterOptionRow, 'Advanced'),
    );
    expect(find.widgetWithText(AsterOptionRow, 'Region'), findsNothing);
    expect(currency.details, 'USD');
    expect(currency.onTap, isNull);
    final currencySemantics = tester
        .getSemantics(find.widgetWithText(AsterOptionRow, 'Currency'))
        .getSemanticsData();
    expect(currencySemantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(currencySemantics.hasAction(ui.SemanticsAction.tap), isFalse);
    unit.onTap!();
    advanced.onTap!();
    await tester.pumpAndSettle();

    expect(find.text('Unit destination'), findsOneWidget);
    expect(find.text('Advanced destination'), findsNothing);
    expect(haptics.intents, [HapticIntent.lightImpact]);
  });

  testWidgets('Advanced shares route ownership with its Back action', (
    tester,
  ) async {
    final haptics = _RecordingHaptics();
    final router = GoRouter(
      initialLocation: '/advanced-test',
      routes: [
        GoRoute(
          path: '/advanced-test',
          builder: (context, state) => const AdvancedSettingsScreen(),
          routes: [
            GoRoute(
              path: RoutePaths.networkConfiguration,
              name: RouteNames.networkConfiguration,
              builder: (context, state) => const Text('Network destination'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpSettingsRouter(tester, router: router, haptics: haptics);
    await tester.pumpAndSettle();

    final network = tester.widget<AsterOptionRow>(
      find.widgetWithText(AsterOptionRow, 'Network configuration'),
    );
    final back = tester.widget<AsterIconButton>(
      find.byWidgetPredicate(
        (widget) => widget is AsterIconButton && widget.tooltip == 'Back',
      ),
    );
    network.onTap!();
    back.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Network destination'), findsOneWidget);
    expect(haptics.intents, [HapticIntent.lightImpact]);
  });

  testWidgets('settings renders real wallet and package metadata only', (
    tester,
  ) async {
    final externalUris = _ExternalUriService();
    await _pumpSettingsScreen(
      tester,
      walletFuture: Future.value(WalletState(activeWallet: _walletProfile)),
      appRepository: SettingsAppRepository(
        _MetadataService(
          const AppResult.success(
            AppBuildMetadata(version: '2.3.4', buildNumber: '81'),
          ),
        ),
        externalUris,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Primary wallet'), findsOneWidget);
    expect(find.text(_walletProfile.displayId), findsOneWidget);
    expect(find.text('Main'), findsNothing);
    expect(find.text('Aster • Version 1.0.0'), findsNothing);
    for (final label in [
      'Contact Support',
      'Twitter',
      'Telegram',
      'Instagram',
      'Notifications',
      'Manage assets',
    ]) {
      expect(find.text(label), findsNothing);
    }

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-version-label')),
      300,
    );
    expect(find.text('Aster • Version 2.3.4 • Build 81'), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const ValueKey('settings-version-label'))).dx,
      closeTo(tester.getCenter(find.byType(SettingsScreen)).dx, 0.01),
    );
    for (final key in [
      'settings-link-termsOfService',
      'settings-link-privacyPolicy',
    ]) {
      final semantics = tester.getSemantics(find.byKey(ValueKey(key)));
      expect(semantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
    }
    expect(find.text('Unavailable'), findsWidgets);
    expect(externalUris.opened, isEmpty);
  });

  testWidgets('wallet failure never falls back to an invented identity', (
    tester,
  ) async {
    final wallet = Completer<WalletState>();
    await _pumpSettingsScreen(
      tester,
      walletFuture: wallet.future,
      appRepository: _appRepository(),
    );

    expect(find.text('Loading wallet'), findsWidgets);
    final walletLoading = find.bySemanticsLabel('Loading wallet');
    expect(walletLoading, findsOneWidget);
    expect(
      tester.getSemantics(walletLoading).flagsCollection.isLiveRegion,
      isTrue,
    );
    expect(find.text('Main'), findsNothing);
    wallet.completeError(
      const AppFailureException(
        AppFailure(
          code: 'wallet_unavailable',
          kind: AppFailureKind.storage,
          userMessage: 'Wallet information is unavailable.',
          retryable: true,
        ),
      ),
      StackTrace.current,
    );
    await tester.pumpAndSettle();

    expect(find.text('Wallet unavailable'), findsOneWidget);
    expect(find.text('Wallet information is unavailable.'), findsOneWidget);
    expect(find.text('Retry wallet'), findsOneWidget);
    expect(find.text('Main'), findsNothing);
  });

  testWidgets('terminal wallet and settings failures expose no retry action', (
    tester,
  ) async {
    final wallet = Completer<WalletState>();
    const walletFailure = AppFailure(
      code: 'wallet_configuration_invalid',
      kind: AppFailureKind.configuration,
      userMessage: 'Wallet information is not configured.',
      retryable: false,
    );
    const settingsFailure = AppFailure(
      code: 'settings_configuration_invalid',
      kind: AppFailureKind.configuration,
      userMessage: 'App settings are not configured.',
      retryable: false,
    );
    await _pumpSettingsScreen(
      tester,
      walletFuture: wallet.future,
      appRepository: _appRepository(),
      settingsViewModelFactory: () =>
          _FailingSettingsViewModel(settingsFailure),
    );
    wallet.completeError(
      const AppFailureException(walletFailure),
      StackTrace.current,
    );
    await tester.pumpAndSettle();

    expect(find.text(walletFailure.userMessage), findsOneWidget);
    expect(find.text(settingsFailure.userMessage), findsOneWidget);
    expect(find.text('Retry wallet'), findsNothing);
    expect(find.text('Retry settings'), findsNothing);
  });

  testWidgets('malformed public links expose a persistent release failure', (
    tester,
  ) async {
    await _pumpSettingsScreen(
      tester,
      walletFuture: Future.value(WalletState(activeWallet: _walletProfile)),
      appRepository: _appRepository(),
      linkConfiguration: PublicLinkConfiguration(
        termsOfService: Uri.parse('http://legal.example.com/terms'),
      ),
    );
    await tester.pumpAndSettle();
    final failure = find.text('Public links are unavailable in this build.');
    await tester.scrollUntilVisible(failure, 300);
    await tester.pump();

    expect(failure, findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    final terms = tester.getSemantics(
      find.byKey(const ValueKey('settings-link-termsOfService')),
    );
    expect(terms.flagsCollection.isEnabled, ui.Tristate.isFalse);
  });

  testWidgets('configured public link reports a bounded launch failure', (
    tester,
  ) async {
    final externalUris = _ExternalUriService(
      result: const AppResult.failure(
        AppFailure(
          code: 'external_uri_open_failed',
          kind: AppFailureKind.unavailable,
          userMessage: 'The link could not be opened.',
          retryable: true,
        ),
      ),
    );
    final haptics = _RecordingHaptics();
    final toasts = _RecordingToasts();
    final terms = Uri.parse('https://legal.example.com/terms');
    await _pumpSettingsScreen(
      tester,
      walletFuture: Future.value(WalletState(activeWallet: _walletProfile)),
      appRepository: SettingsAppRepository(
        _MetadataService(
          const AppResult.success(
            AppBuildMetadata(version: '1.0.0', buildNumber: '2'),
          ),
        ),
        externalUris,
      ),
      linkConfiguration: PublicLinkConfiguration(termsOfService: terms),
      haptics: haptics,
      toasts: toasts,
    );
    await tester.pumpAndSettle();

    final termsRow = find.byKey(const ValueKey('settings-link-termsOfService'));
    await tester.scrollUntilVisible(termsRow, 250);
    expect(
      tester.getSemantics(termsRow).flagsCollection.isEnabled,
      ui.Tristate.isTrue,
    );
    await tester.tap(termsRow);
    await tester.pumpAndSettle();

    expect(externalUris.opened, [terms]);
    expect(haptics.intents, [HapticIntent.error]);
    expect(toasts.messages, ['Link not opened']);
  });

  testWidgets('version failure is explicit and independently retryable', (
    tester,
  ) async {
    final retry = Completer<AppResult<AppBuildMetadata>>();
    final metadata = _QueuedMetadataService([
      Future.value(
        const AppResult.failure(
          AppFailure(
            code: 'metadata_unavailable',
            kind: AppFailureKind.unavailable,
            userMessage: 'The app version could not be loaded.',
            retryable: true,
          ),
        ),
      ),
      retry.future,
    ]);
    await _pumpSettingsScreen(
      tester,
      walletFuture: Future.value(WalletState(activeWallet: _walletProfile)),
      appRepository: SettingsAppRepository(metadata, _ExternalUriService()),
    );
    await tester.pumpAndSettle();
    final retryButton = find.text('Retry version');
    await tester.scrollUntilVisible(retryButton, 300);

    expect(find.text('Aster • Version unavailable'), findsOneWidget);
    await tester.tap(retryButton);
    await tester.pump();
    expect(find.text('Aster • Version loading'), findsOneWidget);
    retry.complete(
      const AppResult.success(
        AppBuildMetadata(version: '3.0.0', buildNumber: ''),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Aster • Version 3.0.0'), findsOneWidget);
    expect(find.text('Retry version'), findsNothing);
  });

  testWidgets('settings remains accessible at compact width and 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpSettingsScreen(
      tester,
      walletFuture: Future.value(WalletState(activeWallet: _walletProfile)),
      appRepository: _appRepository(),
      textScaler: const TextScaler.linear(2),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));
  });
}

Future<void> _pumpPendingSelection(
  WidgetTester tester, {
  required Widget screen,
}) async {
  final pending = Completer<SettingsRepository>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWith((ref) => pending.future),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ),
  );
  await tester.pump();
}

final _walletProfile = WalletProfile(
  id: '0123456789abcdef0123456789abcdef',
  name: 'Primary wallet',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  environment: BlockchainEnvironment.regtest,
  state: WalletProfileState.ready,
  storageToken: 'fedcba9876543210fedcba9876543210',
);

const _nodePublicKey =
    '020000000000000000000000000000000000000000000000000000000000000000';

Future<void> _pumpSettingsScreen(
  WidgetTester tester, {
  required Future<WalletState> walletFuture,
  required SettingsAppRepository appRepository,
  HapticFeedbackService? haptics,
  ToastPresentationService? toasts,
  TextScaler textScaler = TextScaler.noScaling,
  PublicLinkConfiguration linkConfiguration = const PublicLinkConfiguration(),
  SettingsViewModel Function()? settingsViewModelFactory,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settingsRepository = SettingsRepository(
    PreferencesService(await SharedPreferences.getInstance()),
    _CatalogAssetBundle(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        walletViewModelProvider.overrideWith(
          () => _TestWalletViewModel(walletFuture),
        ),
        if (settingsViewModelFactory case final factory?)
          settingsViewModelProvider.overrideWith(factory)
        else
          settingsRepositoryProvider.overrideWith(
            (ref) async => settingsRepository,
          ),
        settingsAppRepositoryProvider.overrideWithValue(appRepository),
        publicLinkConfigurationProvider.overrideWithValue(linkConfiguration),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: AsterFeedbackScope(
            haptics: haptics ?? _RecordingHaptics(),
            toasts: toasts ?? _RecordingToasts(),
            child: child!,
          ),
        ),
        home: const SettingsScreen(),
      ),
    ),
  );
}

Future<void> _pumpSettingsRouter(
  WidgetTester tester, {
  required GoRouter router,
  required HapticFeedbackService haptics,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settingsRepository = SettingsRepository(
    PreferencesService(await SharedPreferences.getInstance()),
    _CatalogAssetBundle(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        walletViewModelProvider.overrideWith(
          () => _TestWalletViewModel(
            Future.value(WalletState(activeWallet: _walletProfile)),
          ),
        ),
        settingsRepositoryProvider.overrideWith(
          (ref) async => settingsRepository,
        ),
        settingsAppRepositoryProvider.overrideWithValue(_appRepository()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder: (context, child) => AsterFeedbackScope(
          haptics: haptics,
          toasts: _RecordingToasts(),
          child: child!,
        ),
      ),
    ),
  );
}

SettingsAppRepository _appRepository() {
  return SettingsAppRepository(
    _MetadataService(
      const AppResult.success(
        AppBuildMetadata(version: '1.0.0', buildNumber: '1'),
      ),
    ),
    _ExternalUriService(),
  );
}

final class _TestWalletViewModel extends WalletViewModel {
  _TestWalletViewModel(this.walletFuture);

  final Future<WalletState> walletFuture;

  @override
  Future<WalletState> build() => walletFuture;
}

final class _CatalogAssetBundle extends CachingAssetBundle {
  static const _sources = {
    'assets/data/currencies.json': '[{"name":"United States Dollar","symbol":"\$","code":"USD","countryCode":"US"}]',
    'assets/data/countries.json': '[{"name":"United States","code":"US"}]',
  };

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(_sources[key]!));
    return ByteData.sublistView(bytes);
  }
}

final class _FailingPreferencesService extends PreferencesService {
  _FailingPreferencesService(super.preferences);

  @override
  Future<void> setString(String key, String value) {
    throw StateError('Injected preference write failure.');
  }
}

final class _StaticNetworkConfigurationViewModel
    extends NetworkConfigurationViewModel {
  _StaticNetworkConfigurationViewModel(this.value);

  final NetworkConfigurationState value;

  @override
  Future<NetworkConfigurationState> build() async => value;
}

final class _FailingNetworkConfigurationViewModel
    extends NetworkConfigurationViewModel {
  _FailingNetworkConfigurationViewModel(this.failure);

  final AppFailure failure;

  @override
  Future<NetworkConfigurationState> build() {
    return Future.error(AppFailureException(failure), StackTrace.current);
  }
}

final class _PendingSettingsViewModel extends SettingsViewModel {
  _PendingSettingsViewModel(this._future);

  final Future<SettingsState> _future;

  @override
  Future<SettingsState> build() => _future;
}

final class _StaticSettingsViewModel extends SettingsViewModel {
  _StaticSettingsViewModel(this.value);

  final SettingsState value;

  @override
  Future<SettingsState> build() async => value;
}

final _selectionState = SettingsState(
  snapshot: SettingsSnapshot(
    preferences: AppPreferences.defaults,
    currencies: [
      FiatCurrency(
        name: 'United States Dollar',
        symbol: r'$',
        code: 'USD',
        countryCode: 'US',
      ),
      FiatCurrency(name: 'Euro', symbol: 'EUR', code: 'EUR', countryCode: 'DE'),
    ],
    regions: [
      Region(name: 'United States', code: 'US'),
      Region(name: 'Germany', code: 'DE'),
    ],
  ),
);

final class _ControlledSettingsViewModel extends SettingsViewModel {
  _ControlledSettingsViewModel(this.initialState);

  final SettingsState initialState;
  final Completer<void> _gate = Completer<void>();

  @override
  Future<SettingsState> build() async => initialState;

  @override
  Future<bool> selectCurrency(String code) => _hold(SettingsOperation.currency);

  @override
  Future<bool> selectRegion(String code) => _hold(SettingsOperation.region);

  @override
  Future<bool> selectBitcoinUnit(BitcoinUnit unit) =>
      _hold(SettingsOperation.bitcoinUnit);

  Future<bool> _hold(SettingsOperation operation) async {
    final current = state.requireValue;
    state = AsyncData(current.copyWith(operation: operation));
    await _gate.future;
    if (ref.mounted) state = AsyncData(current);
    return false;
  }

  void complete() => _gate.complete();
}

final class _FailingSettingsViewModel extends SettingsViewModel {
  _FailingSettingsViewModel(this.failure);

  final AppFailure failure;

  @override
  Future<SettingsState> build() {
    return Future.error(AppFailureException(failure), StackTrace.current);
  }
}

final class _MetadataService implements AppMetadataService {
  _MetadataService(this.result);

  final AppResult<AppBuildMetadata> result;

  @override
  Future<AppResult<AppBuildMetadata>> load() async => result;
}

final class _QueuedMetadataService implements AppMetadataService {
  _QueuedMetadataService(this.responses);

  final List<Future<AppResult<AppBuildMetadata>>> responses;

  @override
  Future<AppResult<AppBuildMetadata>> load() {
    if (responses.isEmpty) throw StateError('No metadata response queued.');
    return responses.removeAt(0);
  }
}

final class _ExternalUriService implements ExternalUriService {
  _ExternalUriService({this.result = const AppResult.success(null)});

  final AppResult<void> result;
  final opened = <Uri>[];

  @override
  Future<AppResult<void>> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

final class _RecordingHaptics implements HapticFeedbackService {
  final intents = <HapticIntent>[];

  @override
  Future<void> trigger(HapticIntent intent) async => intents.add(intent);
}

final class _RecordingToasts implements ToastPresentationService {
  final messages = <String>[];

  @override
  void dismissCurrent({int? id}) {}

  @override
  bool show({
    required String title,
    required ToastVariant variant,
    String? message,
    Duration? duration,
  }) {
    messages.add(title);
    return true;
  }
}

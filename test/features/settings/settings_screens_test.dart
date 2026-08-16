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
      'utexo.settings.v1.currency': 'USD',
      'utexo.settings.v1.region': 'US',
      'utexo.settings.v1.bitcoin_unit': 'btc',
      'utexo.settings.v1.balances_visible': true,
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

  testWidgets('network refresh remains explicitly announced', (tester) async {
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

  testWidgets('terminal network health failure has no retry action', (
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
              const NetworkConfigurationState(
                configuration: configuration,
                healthFailure: AppFailure(
                  code: 'network_configuration_invalid',
                  kind: AppFailureKind.configuration,
                  userMessage: 'Network configuration is invalid.',
                  retryable: false,
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

    final failure = find.text('Network configuration is invalid.');
    await tester.scrollUntilVisible(failure, 300);
    await tester.pump();
    expect(failure, findsOneWidget);
    expect(find.text('Retry health check'), findsNothing);
  });

  testWidgets('advanced disclosures are disabled without auth policy', (
    tester,
  ) async {
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
    final seedSemantics = tester.getSemantics(find.text('Check seed phrase'));
    expect(exportSemantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(seedSemantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(find.text('Unavailable'), findsNWidgets(2));
    expect(haptics.intents, isEmpty);
  });

  testWidgets('Settings owns one navigation command across preference rows', (
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
              path: RoutePaths.currencySelection,
              name: RouteNames.currencySelection,
              builder: (context, state) => const Text('Currency destination'),
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
    currency.onTap!();
    unit.onTap!();
    await tester.pumpAndSettle();

    expect(find.text('Currency destination'), findsOneWidget);
    expect(find.text('Unit destination'), findsNothing);
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
    expect(find.text('UTEXO • Version 1.0.0'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-version-label')),
      300,
    );
    expect(find.text('UTEXO • Version 2.3.4 (81)'), findsOneWidget);
    for (final key in [
      'settings-link-contactSupport',
      'settings-link-termsOfService',
      'settings-link-privacyPolicy',
      'settings-link-twitter',
      'settings-link-telegram',
      'settings-link-instagram',
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
        contactSupport: Uri.parse('http://support.example.com'),
      ),
    );
    await tester.pumpAndSettle();
    final failure = find.text('Public links are unavailable in this build.');
    await tester.scrollUntilVisible(failure, 300);
    await tester.pump();

    expect(failure, findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    final support = tester.getSemantics(
      find.byKey(const ValueKey('settings-link-contactSupport')),
    );
    expect(support.flagsCollection.isEnabled, ui.Tristate.isFalse);
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
    final support = Uri.parse('https://support.example.com/help');
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
      linkConfiguration: PublicLinkConfiguration(contactSupport: support),
      haptics: haptics,
      toasts: toasts,
    );
    await tester.pumpAndSettle();

    final supportRow = find.byKey(
      const ValueKey('settings-link-contactSupport'),
    );
    await tester.scrollUntilVisible(supportRow, 250);
    expect(
      tester.getSemantics(supportRow).flagsCollection.isEnabled,
      ui.Tristate.isTrue,
    );
    await tester.tap(supportRow);
    await tester.pumpAndSettle();

    expect(externalUris.opened, [support]);
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

    expect(find.text('UTEXO • Version unavailable'), findsOneWidget);
    await tester.tap(retryButton);
    await tester.pump();
    expect(find.text('UTEXO • Version loading'), findsOneWidget);
    retry.complete(
      const AppResult.success(
        AppBuildMetadata(version: '3.0.0', buildNumber: ''),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('UTEXO • Version 3.0.0'), findsOneWidget);
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

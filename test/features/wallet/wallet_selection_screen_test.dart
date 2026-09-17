import 'dart:async';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/pages/wallet_selection_screen.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:aster/features/wallet/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/presentation_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'wallet switch owns truthful semantics, progress, and failure feedback',
    (tester) async {
      final viewModel = _ControlledWalletViewModel(_walletState);
      final harness = await _pumpWalletSelection(tester, viewModel);
      final selected = tester.getSemantics(
        find.bySemanticsLabel(_primaryLabel),
      );
      final available = tester.getSemantics(
        find.bySemanticsLabel(_backupLabel),
      );
      expect(
        selected.getSemanticsData().flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        selected.getSemanticsData().flagsCollection.isEnabled,
        ui.Tristate.isTrue,
      );
      expect(
        selected.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isFalse,
      );
      expect(
        available.getSemanticsData().flagsCollection.isSelected,
        ui.Tristate.isFalse,
      );
      expect(
        available.getSemanticsData().flagsCollection.isEnabled,
        ui.Tristate.isTrue,
      );
      expect(
        available.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.bySemanticsLabel(_backupLabel));
      await tester.pump();

      expect(viewModel.switchAttempts, 1);
      expect(harness.haptics.intents, isEmpty);
      expect(find.byType(GridLoader), findsOneWidget);
      final switching = tester
          .getSemantics(find.bySemanticsLabel(_backupLabel))
          .getSemanticsData();
      expect(switching.flagsCollection.isEnabled, ui.Tristate.isFalse);
      expect(switching.value, 'Switching');
      expect(switching.hasAction(ui.SemanticsAction.tap), isFalse);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Add wallet'))
            .flagsCollection
            .isEnabled,
        ui.Tristate.isFalse,
      );
      final blockedBack = tester
          .getSemantics(find.bySemanticsLabel('Back'))
          .getSemanticsData();
      expect(blockedBack.flagsCollection.isEnabled, ui.Tristate.isFalse);
      expect(blockedBack.hasAction(ui.SemanticsAction.tap), isFalse);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(WalletSelectionScreen), findsOneWidget);

      await tester.tap(
        find.bySemanticsLabel(_backupLabel),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(viewModel.switchAttempts, 1);

      viewModel.completeFailure(_switchFailure);
      await _pumpFrames(tester);

      expect(find.byType(WalletSelectionScreen), findsOneWidget);
      expect(find.text('Settings root'), findsNothing);
      expect(harness.haptics.intents, [HapticIntent.error]);
      expect(harness.toasts.messages, hasLength(1));
      expect(harness.toasts.messages.single.title, 'Wallet not switched');
      expect(
        harness.toasts.messages.single.message,
        _switchFailure.userMessage,
      );
      expect(harness.toasts.messages.single.variant, ToastVariant.failure);
      expect(viewModel.state.value?.operationFailure, isNull);
      expect(find.byType(GridLoader), findsNothing);
      final idleBack = tester
          .getSemantics(find.bySemanticsLabel('Back'))
          .getSemanticsData();
      expect(idleBack.flagsCollection.isEnabled, ui.Tristate.isTrue);
      expect(idleBack.hasAction(ui.SemanticsAction.tap), isTrue);
    },
  );

  testWidgets('wallet switch navigates only after a confirmed commit', (
    tester,
  ) async {
    final viewModel = _ControlledWalletViewModel(_walletState);
    final harness = await _pumpWalletSelection(tester, viewModel);

    await tester.tap(find.bySemanticsLabel(_backupLabel));
    await tester.pump();
    expect(find.byType(WalletSelectionScreen), findsOneWidget);
    expect(harness.haptics.intents, isEmpty);

    viewModel.completeSuccess();
    await _pumpFrames(tester);
    await harness.routeCompletion;
    await tester.pump();

    expect(_location(harness.router), RoutePaths.settings);
    expect(find.byType(WalletSelectionScreen), findsNothing);
    expect(find.text('Settings root'), findsOneWidget);
    expect(viewModel.state.value?.activeWallet, _backupWallet);
    expect(harness.haptics.intents, [HapticIntent.selection]);
    expect(harness.toasts.messages, isEmpty);
  });

  testWidgets('Add wallet action opens the dedicated wallet setup flow', (
    tester,
  ) async {
    await _pumpWalletSelection(
      tester,
      _ControlledWalletViewModel(_walletState),
    );

    final add = find.bySemanticsLabel('Add wallet');
    expect(add, findsOneWidget);
    expect(
      tester.getSemantics(add).flagsCollection.isEnabled,
      ui.Tristate.isTrue,
    );
    final addButton = tester.widget<AsterIconButton>(
      find.byWidgetPredicate(
        (widget) => widget is AsterIconButton && widget.tooltip == 'Add wallet',
      ),
    );
    addButton.onPressed!();
    await tester.pump();
    await _pumpFrames(tester);

    expect(find.text('Add wallet destination'), findsOneWidget);
  });

  testWidgets(
    'wallet switch blocks stale Back and system pop in its first frame',
    (tester) async {
      final viewModel = _ControlledWalletViewModel(_walletState);
      final harness = await _pumpWalletSelection(tester, viewModel);
      final walletRow = tester.widget<WalletSelectOptionRow>(
        find.byKey(ValueKey('wallet-${_backupWallet.id}')),
      );
      final back = tester.widget<AsterIconButton>(
        find.byWidgetPredicate(
          (widget) => widget is AsterIconButton && widget.tooltip == 'Back',
        ),
      );
      final navigation = AsterNavigationScope.of(
        tester.element(find.bySemanticsLabel('Back')),
      );

      walletRow.onTap!();
      expect(navigation.inFlight, isTrue);
      expect(harness.router.canPop(), isTrue);
      back.onPressed!();
      expect(harness.router.canPop(), isTrue);
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(harness.router.canPop(), isTrue);
      expect(find.byType(WalletSelectionScreen), findsOneWidget);
      expect(viewModel.switchAttempts, 1);

      viewModel.completeFailure(_switchFailure);
      await _pumpFrames(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_location(harness.router), RoutePaths.settings);
      expect(find.text('Settings root'), findsOneWidget);
    },
  );

  testWidgets(
    'initial loading has one live label and compact rows do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<WalletState>();
      await _pumpWalletSelection(
        tester,
        _FutureWalletViewModel(pending.future),
        textScaler: const TextScaler.linear(2),
      );
      expect(find.bySemanticsLabel('Loading wallets'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      pending.complete(_walletState);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(_primaryLabel), findsOneWidget);
      expect(find.bySemanticsLabel(_backupLabel), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    },
  );

  for (final vector in <({bool retryable, bool showsRetry})>[
    (retryable: true, showsRetry: true),
    (retryable: false, showsRetry: false),
  ]) {
    testWidgets('wallet load failure respects retryable=${vector.retryable}', (
      tester,
    ) async {
      final failure = AppFailure(
        code: 'wallet_test_load',
        kind: AppFailureKind.storage,
        userMessage: vector.retryable
            ? 'Wallet storage is temporarily unavailable.'
            : 'Wallet storage requires recovery.',
        retryable: vector.retryable,
      );
      await _pumpWalletSelection(tester, _FailingWalletViewModel(failure));

      expect(find.text(failure.userMessage), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(failure.userMessage))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(
        find.widgetWithText(CustomButton, 'Retry'),
        vector.showsRetry ? findsOneWidget : findsNothing,
      );
    });
  }
}

const _walletPath = '${RoutePaths.settings}/${RoutePaths.walletSelection}';

final _primaryWallet = WalletProfile(
  id: '11111111111111111111111111111111',
  name: 'Primary wallet',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  environment: BlockchainEnvironment.regtest,
  state: WalletProfileState.ready,
  storageToken: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
);

final _backupWallet = WalletProfile(
  id: '22222222222222222222222222222222',
  name: 'Long secondary wallet name for compact layouts',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  environment: BlockchainEnvironment.regtest,
  state: WalletProfileState.ready,
  storageToken: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
);

final _walletState = WalletState(
  wallets: [_primaryWallet, _backupWallet],
  activeWallet: _primaryWallet,
);

final _switchFailure = AppFailure(
  code: 'wallet_test_switch',
  kind: AppFailureKind.storage,
  userMessage: 'The wallet could not be switched safely.',
  retryable: true,
);

String get _primaryLabel =>
    '${_primaryWallet.name}, ${_primaryWallet.displayId}';
String get _backupLabel => '${_backupWallet.name}, ${_backupWallet.displayId}';

Future<_WalletSelectionHarness> _pumpWalletSelection(
  WidgetTester tester,
  WalletViewModel viewModel, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final haptics = RecordingHapticFeedbackService();
  final toasts = RecordingToastPresentationService();
  final router = GoRouter(
    initialLocation: RoutePaths.settings,
    routes: [
      GoRoute(
        path: RoutePaths.settings,
        builder: (context, state) =>
            const Scaffold(body: Text('Settings root')),
        routes: [
          GoRoute(
            path: RoutePaths.walletSelection,
            builder: (context, state) => const WalletSelectionScreen(),
            routes: [
              GoRoute(
                path: RoutePaths.addWallet,
                name: RouteNames.addWallet,
                builder: (context, state) =>
                    const Scaffold(body: Text('Add wallet destination')),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [walletViewModelProvider.overrideWith(() => viewModel)],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: AsterFeedbackScope(
            haptics: haptics,
            toasts: toasts,
            child: child!,
          ),
        ),
      ),
    ),
  );
  final routeCompletion = router.push<Object?>(_walletPath);
  await _pumpFrames(tester);
  return _WalletSelectionHarness(
    router: router,
    routeCompletion: routeCompletion,
    haptics: haptics,
    toasts: toasts,
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 80; frame += 1) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

final class _WalletSelectionHarness {
  const _WalletSelectionHarness({
    required this.router,
    required this.routeCompletion,
    required this.haptics,
    required this.toasts,
  });

  final GoRouter router;
  final Future<Object?> routeCompletion;
  final RecordingHapticFeedbackService haptics;
  final RecordingToastPresentationService toasts;
}

final class _FutureWalletViewModel extends WalletViewModel {
  _FutureWalletViewModel(this._result);

  final Future<WalletState> _result;

  @override
  Future<WalletState> build() => _result;
}

final class _FailingWalletViewModel extends WalletViewModel {
  _FailingWalletViewModel(this.failure);

  final AppFailure failure;

  @override
  Future<WalletState> build() async {
    await Future<void>.delayed(Duration.zero);
    throw AppFailureException(failure);
  }
}

final class _ControlledWalletViewModel extends WalletViewModel {
  _ControlledWalletViewModel(this.initialState);

  final WalletState initialState;
  Completer<AppFailure?>? _pendingSwitch;
  var switchAttempts = 0;

  @override
  Future<WalletState> build() async => initialState;

  @override
  Future<bool> switchWallet(String walletId) async {
    final current = state.value;
    if (current == null || current.switchingWalletId != null) return false;
    final target = current.wallets.singleWhere(
      (wallet) => wallet.id == walletId,
    );
    final pending = Completer<AppFailure?>();
    _pendingSwitch = pending;
    switchAttempts += 1;
    state = AsyncData(
      current.copyWith(switchingWalletId: walletId, operationFailure: null),
    );
    final failure = await pending.future;
    _pendingSwitch = null;
    if (!ref.mounted) return failure == null;
    if (failure != null) {
      state = AsyncData(
        current.copyWith(switchingWalletId: null, operationFailure: failure),
      );
      return false;
    }
    state = AsyncData(
      current.copyWith(
        activeWallet: target,
        switchingWalletId: null,
        operationFailure: null,
      ),
    );
    return true;
  }

  void completeSuccess() => _pendingSwitch!.complete();

  void completeFailure(AppFailure failure) => _pendingSwitch!.complete(failure);
}

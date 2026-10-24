import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';
import 'create_wallet_quiz_screen.dart';
import 'onboarding_create_wallet_screen.dart';
import 'onboarding_import_wallet_screen.dart';
import 'onboarding_shell.dart';
import 'wallet_name_screen.dart';

/// Presents the first-wallet journey inside the route-owned onboarding shell.
class OnboardingWelcomeScreen extends StatelessWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _WalletSetupJourney(origin: WalletCreationOrigin.onboarding);
  }
}

/// Presents additional-wallet setup over the same retained brand artwork.
class AddWalletScreen extends StatelessWidget {
  const AddWalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingShell(
      child: _WalletSetupJourney(origin: WalletCreationOrigin.walletSelector),
    );
  }
}

/// Owns one complete create-or-import journey on a single route.
///
/// Phrase generation, validation, and provisioning remain in their dedicated
/// ViewModels. This coordinator owns only presentation order and back behavior,
/// so step changes do not create overlapping routes or duplicate native work.
class _WalletSetupJourney extends ConsumerStatefulWidget {
  const _WalletSetupJourney({required this.origin});

  final WalletCreationOrigin origin;

  @override
  ConsumerState<_WalletSetupJourney> createState() =>
      _WalletSetupJourneyState();
}

enum _WalletSetupStep {
  welcome,
  createRecoveryPhrase,
  createRecoveryQuiz,
  createWalletName,
  importRecoveryPhrase,
  importWalletName,
}

class _WalletSetupJourneyState extends ConsumerState<_WalletSetupJourney>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  _WalletSetupStep _step = _WalletSetupStep.welcome;
  _WalletSetupStep? _outgoingStep;
  late final AnimationController _transitionController;
  var _checkingDictionary = false;
  var _dictionaryCheckDeparted = false;
  var _dictionaryCheckRevision = 0;

  bool get _transitioning => _outgoingStep != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _transitionController = AnimationController(vsync: this, value: 1)
      ..addStatusListener(_handleTransitionStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.isCurrentOf(context);
    TickerMode.valuesOf(context);
    if (_checkingDictionary && !_ownsWelcomeInteraction) {
      _dictionaryCheckDeparted = true;
    }
    final previous = _outgoingStep;
    final duration = _transitionDuration;
    _transitionController.duration = duration;
    if (duration == Duration.zero && previous != null) {
      _transitionController.stop();
      _outgoingStep = null;
      _transitionController.value = 1;
      _disposeAbandonedBranch(previous, _step);
    }
  }

  @override
  void dispose() {
    _dictionaryCheckRevision += 1;
    WidgetsBinding.instance.removeObserver(this);
    _transitionController
      ..removeStatusListener(_handleTransitionStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the same cached repository alive from preflight through the form.
    ref.watch(walletSetupPreflightViewModelProvider);
    final operationLocked = switch (_step) {
      _WalletSetupStep.createRecoveryPhrase ||
      _WalletSetupStep.createRecoveryQuiz ||
      _WalletSetupStep.createWalletName => _createOperationLocked(),
      _WalletSetupStep.importRecoveryPhrase ||
      _WalletSetupStep.importWalletName => _importOperationLocked(),
      _WalletSetupStep.welcome => _checkingDictionary,
    };

    final canLeaveRoute =
        widget.origin == WalletCreationOrigin.walletSelector &&
        _step == _WalletSetupStep.welcome &&
        !_checkingDictionary &&
        !_transitioning;
    return PopScope(
      canPop: canLeaveRoute,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_transitioning && !operationLocked) {
          _showPreviousStep(hapticIntent: null);
        }
      },
      child: AbsorbPointer(
        absorbing: _transitioning,
        child: ExcludeSemantics(
          excluding: _transitioning,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_outgoingStep case final outgoing?)
                _buildStepTransition(step: outgoing, ignorePointer: true),
              _buildStepTransition(step: _step, ignorePointer: false),
              if (_journeyChromeStep case final chromeStep?)
                KeyedSubtree(
                  key: const ValueKey('wallet-setup-journey-chrome'),
                  child: _buildJourneyChrome(
                    step: chromeStep,
                    operationLocked: operationLocked,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || !_checkingDictionary) return;
    _dictionaryCheckDeparted = true;
  }

  bool get _ownsWelcomeInteraction =>
      mounted &&
      _step == _WalletSetupStep.welcome &&
      !_transitioning &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  Future<void> _openRecoveryStep(
    _WalletSetupStep next,
    AsterNavigationCommandOwner navigation,
  ) async {
    if (_checkingDictionary || !_ownsWelcomeInteraction) return;
    final toasts = context.toasts;
    final revision = ++_dictionaryCheckRevision;
    _dictionaryCheckDeparted = false;
    setState(() => _checkingDictionary = true);
    await navigation.run(
      command: () async {
        AppFailure? failure;
        try {
          final result = await ref
              .read(walletSetupPreflightViewModelProvider)
              .prepareRecoveryPhrase();
          if (result case AppFailureResult(failure: final value)) {
            failure = value;
          }
        } catch (error, stackTrace) {
          failure = FailureMapper.from(error, stackTrace);
        }
        if (!mounted ||
            revision != _dictionaryCheckRevision ||
            _dictionaryCheckDeparted ||
            !_ownsWelcomeInteraction) {
          return;
        }
        if (failure != null) {
          unawaited(context.haptics.trigger(HapticIntent.error));
          toasts.show(
            title: 'Wallet setup unavailable',
            message: failure.userMessage,
            variant: ToastVariant.failure,
          );
        } else {
          _showStep(next);
        }
      },
      failureTitle: 'Wallet setup unavailable',
      hapticIntent: null,
      blocksRoutePop: true,
    );
    if (mounted && revision == _dictionaryCheckRevision) {
      setState(() => _checkingDictionary = false);
    }
  }

  /// Gives every step the same shared, item-level choreography timeline.
  Widget _buildStepTransition({
    required _WalletSetupStep step,
    required bool ignorePointer,
  }) {
    return KeyedSubtree(
      key: ValueKey(step),
      child: IgnorePointer(
        ignoring: ignorePointer,
        child: OnboardingChoreographyScope(
          animation: _transitionController,
          exiting: ignorePointer,
          child: _buildStep(step),
        ),
      ),
    );
  }

  void _handleTransitionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final previous = _outgoingStep;
    if (previous == null) return;
    setState(() => _outgoingStep = null);
    _disposeAbandonedBranch(previous, _step);
  }

  bool _createOperationLocked() {
    final value = ref.watch(createWalletViewModelProvider).value;
    return value?.submitting == true ||
        value?.completed == true ||
        value?.requiresReconciliation == true;
  }

  bool _importOperationLocked() {
    final value = ref.watch(importWalletViewModelProvider).value;
    return value?.submitting == true ||
        value?.completed == true ||
        value?.requiresReconciliation == true;
  }

  Widget _buildStep(_WalletSetupStep step) {
    return switch (step) {
      _WalletSetupStep.welcome => AsterNavigationScope(
        child: Builder(
          builder: (context) {
            final navigation = AsterNavigationScope.of(context);
            return _WalletSetupWelcomeContent(
              origin: widget.origin,
              checkingDictionary: _checkingDictionary,
              onBack:
                  widget.origin == WalletCreationOrigin.walletSelector &&
                      !_checkingDictionary
                  ? () {
                      if (_checkingDictionary || !_ownsWelcomeInteraction) {
                        return;
                      }
                      Navigator.of(context).pop();
                    }
                  : null,
              onCreateWallet: () => unawaited(
                _openRecoveryStep(
                  _WalletSetupStep.createRecoveryPhrase,
                  navigation,
                ),
              ),
              onImportWallet: () => unawaited(
                _openRecoveryStep(
                  _WalletSetupStep.importRecoveryPhrase,
                  navigation,
                ),
              ),
            );
          },
        ),
      ),
      _WalletSetupStep.createRecoveryPhrase => OnboardingCreateWalletScreen(
        onBack: _showPreviousStep,
        onContinue: () => _showStep(_WalletSetupStep.createRecoveryQuiz),
        onBrandArt: true,
        showNavigationBar: false,
      ),
      _WalletSetupStep.createRecoveryQuiz => CreateWalletQuizScreen(
        onBack: _showPreviousStep,
        onContinue: () => _showStep(_WalletSetupStep.createWalletName),
        onBrandArt: true,
        showNavigationBar: false,
      ),
      _WalletSetupStep.createWalletName => WalletNameScreen.create(
        onBack: _showPreviousStep,
        onCompleted: _completeJourney,
        onBrandArt: true,
        showNavigationBar: false,
      ),
      _WalletSetupStep.importRecoveryPhrase => OnboardingImportWalletScreen(
        onBack: _showPreviousStep,
        onContinue: () => _showStep(_WalletSetupStep.importWalletName),
        onBrandArt: true,
        showNavigationBar: false,
      ),
      _WalletSetupStep.importWalletName => WalletNameScreen.import(
        onBack: _showPreviousStep,
        onCompleted: _completeJourney,
        onBrandArt: true,
        showNavigationBar: false,
      ),
    };
  }

  _WalletSetupStep? get _journeyChromeStep {
    if (_step != _WalletSetupStep.welcome) return _step;
    final outgoing = _outgoingStep;
    return outgoing != null && outgoing != _WalletSetupStep.welcome
        ? outgoing
        : null;
  }

  Widget _buildJourneyChrome({
    required _WalletSetupStep step,
    required bool operationLocked,
  }) {
    final progress = _progressFor(step);
    if (progress == null) return const SizedBox.shrink();

    final chrome = SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: context.metrics.appBarHeight,
          child: Row(
            children: [
              AsterIconButton(
                icon: MingCuteIcons.mgc_left_line,
                tooltip: 'Back',
                onPressed: !_transitioning && !operationLocked
                    ? _showPreviousStep
                    : null,
                color: context.appColors.onBrandArt,
                hapticIntent: null,
                alignment: Alignment.centerRight,
              ),
              const Spacer(),
              Padding(
                padding: EdgeInsets.only(right: context.spacing.screenPadding),
                child: OnboardingStepIndicator(
                  currentStep: progress.currentStep,
                  stepCount: progress.stepCount,
                  onBrandArt: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final crossingWelcome =
        _outgoingStep == _WalletSetupStep.welcome ||
        _step == _WalletSetupStep.welcome;
    if (!crossingWelcome) return chrome;

    return OnboardingChoreographyScope(
      animation: _transitionController,
      exiting: _step == _WalletSetupStep.welcome,
      child: OnboardingChoreographyItem(
        id: 'wallet-setup-journey-chrome-motion',
        visualIndex: 0,
        child: chrome,
      ),
    );
  }

  ({int currentStep, int stepCount})? _progressFor(_WalletSetupStep step) {
    return switch (step) {
      _WalletSetupStep.createRecoveryPhrase => (currentStep: 0, stepCount: 3),
      _WalletSetupStep.createRecoveryQuiz => (currentStep: 1, stepCount: 3),
      _WalletSetupStep.createWalletName => (currentStep: 2, stepCount: 3),
      _WalletSetupStep.importRecoveryPhrase => (currentStep: 0, stepCount: 2),
      _WalletSetupStep.importWalletName => (currentStep: 1, stepCount: 2),
      _WalletSetupStep.welcome => null,
    };
  }

  void _showPreviousStep({
    HapticIntent? hapticIntent = HapticIntent.lightImpact,
  }) {
    if (_checkingDictionary) return;
    final previous = switch (_step) {
      _WalletSetupStep.welcome => null,
      _WalletSetupStep.createRecoveryPhrase => _WalletSetupStep.welcome,
      _WalletSetupStep.createRecoveryQuiz =>
        _WalletSetupStep.createRecoveryPhrase,
      _WalletSetupStep.createWalletName => _WalletSetupStep.createRecoveryQuiz,
      _WalletSetupStep.importRecoveryPhrase => _WalletSetupStep.welcome,
      _WalletSetupStep.importWalletName =>
        _WalletSetupStep.importRecoveryPhrase,
    };
    if (previous == null) return;
    _discardNameDraft(_step);
    _showStep(previous, hapticIntent: hapticIntent);
  }

  void _completeJourney() {
    if (!mounted) return;
    context.go(RoutePaths.home);
  }

  void _discardNameDraft(_WalletSetupStep step) {
    switch (step) {
      case _WalletSetupStep.createWalletName:
        ref
            .read(createWalletViewModelProvider.notifier)
            .discardWalletNameDraft();
      case _WalletSetupStep.importWalletName:
        ref
            .read(importWalletViewModelProvider.notifier)
            .discardWalletNameDraft();
      case _WalletSetupStep.welcome ||
          _WalletSetupStep.createRecoveryPhrase ||
          _WalletSetupStep.createRecoveryQuiz ||
          _WalletSetupStep.importRecoveryPhrase:
        break;
    }
  }

  void _showStep(
    _WalletSetupStep next, {
    HapticIntent? hapticIntent = HapticIntent.lightImpact,
  }) {
    if (!mounted || _transitioning || next == _step) return;
    final previous = _step;
    FocusManager.instance.primaryFocus?.unfocus();
    if (hapticIntent case final intent?) {
      unawaited(context.haptics.trigger(intent));
    }
    final duration = _transitionDuration;
    if (duration == Duration.zero) {
      setState(() => _step = next);
      _disposeAbandonedBranch(previous, next);
      return;
    }
    _transitionController.duration = duration;
    setState(() {
      _outgoingStep = previous;
      _step = next;
    });
    unawaited(_transitionController.forward(from: 0));
  }

  Duration get _transitionDuration => context.motionPolicy.duration(
    context.motion.onboardingStepTransitionDuration,
  );

  void _disposeAbandonedBranch(
    _WalletSetupStep previous,
    _WalletSetupStep next,
  ) {
    if (next != _WalletSetupStep.welcome) return;
    switch (previous) {
      case _WalletSetupStep.createRecoveryPhrase:
        ref.invalidate(createWalletViewModelProvider);
      case _WalletSetupStep.importRecoveryPhrase:
        ref.invalidate(importWalletViewModelProvider);
      case _WalletSetupStep.welcome ||
          _WalletSetupStep.createRecoveryQuiz ||
          _WalletSetupStep.createWalletName ||
          _WalletSetupStep.importWalletName:
        break;
    }
  }
}

class _WalletSetupWelcomeContent extends StatelessWidget {
  const _WalletSetupWelcomeContent({
    required this.origin,
    required this.onBack,
    required this.onCreateWallet,
    required this.onImportWallet,
    required this.checkingDictionary,
  });

  final WalletCreationOrigin origin;
  final VoidCallback? onBack;
  final VoidCallback onCreateWallet;
  final VoidCallback onImportWallet;
  final bool checkingDictionary;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final type = context.type;
    return Scaffold(
      backgroundColor: context.appColors.transparentSurface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            ...switch (origin) {
              WalletCreationOrigin.onboarding => [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    spacing.xxl,
                    spacing.xxl,
                    spacing.xxl,
                    spacing.lg,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OnboardingChoreographyItem(
                          id: 'welcome-header-motion',
                          visualIndex: 0,
                          child: const OnboardingWelcomeHeader(
                            onBrandArt: true,
                          ),
                        ),
                        SizedBox(height: spacing.huge),
                        OnboardingChoreographyItem(
                          id: 'welcome-grid-motion',
                          visualIndex: 1,
                          child: const OnboardingWelcomeIconGrid(),
                        ),
                        SizedBox(height: spacing.xxxl),
                        OnboardingChoreographyItem(
                          id: 'welcome-message-motion',
                          visualIndex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Built for\nUSDT on Bitcoin',
                                style: type.brandHero,
                              ),
                              SizedBox(height: spacing.md),
                              Text(
                                'One wallet for Bitcoin, USDT and RGB assets.',
                                style: type.brandBody,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              WalletCreationOrigin.walletSelector => [
                SliverToBoxAdapter(
                  child: OnboardingChoreographyItem(
                    id: 'add-wallet-nav-motion',
                    visualIndex: 0,
                    child: SizedBox(
                      height: context.metrics.appBarHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AsterIconButton(
                          icon: MingCuteIcons.mgc_left_line,
                          tooltip: 'Back',
                          onPressed: onBack,
                          color: context.appColors.onBrandArt,
                          hapticIntent: null,
                          alignment: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    spacing.screenPadding,
                    spacing.lg,
                    spacing.screenPadding,
                    spacing.lg,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: OnboardingChoreographyItem(
                      id: 'add-wallet-copy-motion',
                      visualIndex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Multiple wallets,\none Aster',
                            style: type.pageTitle.copyWith(
                              color: context.appColors.onBrandArt,
                            ),
                          ),
                          SizedBox(height: spacing.sm),
                          Text(
                            'Create or import another wallet, then switch '
                            'between your wallets whenever you need.',
                            style: type.rowMeta.copyWith(
                              color: context.appColors.onBrandArt.withValues(
                                alpha:
                                    context.effects.brandContentStrongOpacity,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            },
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.xxl,
                  0,
                  spacing.xxl,
                  spacing.xxl,
                ),
                child: OnboardingChoreographyItem(
                  id: 'welcome-actions-motion',
                  visualIndex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CustomButton(
                        text: switch (origin) {
                          WalletCreationOrigin.onboarding => 'Create Wallet',
                          WalletCreationOrigin.walletSelector =>
                            'Add New Wallet',
                        },
                        variant: ButtonVariant.translucent,
                        hapticIntent: null,
                        loading: checkingDictionary,
                        enabled: !checkingDictionary,
                        onTap: onCreateWallet,
                      ),
                      SizedBox(height: spacing.sm),
                      OnboardingTextAction(
                        label: 'Import Wallet',
                        onBrandArt: true,
                        hapticIntent: null,
                        enabled: !checkingDictionary,
                        onPressed: onImportWallet,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

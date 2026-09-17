import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Imports a wallet through 12 per-word fields and SDK checksum validation.
class OnboardingImportWalletScreen extends ConsumerStatefulWidget {
  const OnboardingImportWalletScreen({super.key});

  @override
  ConsumerState<OnboardingImportWalletScreen> createState() =>
      _OnboardingImportWalletScreenState();
}

class _OnboardingImportWalletScreenState
    extends ConsumerState<OnboardingImportWalletScreen> {
  late final PageController _pageController;
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  var _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _controllers = List.generate(
      ImportWalletState.wordCount,
      (_) => TextEditingController(),
    );
    _focusNodes = List.generate(
      ImportWalletState.wordCount,
      (index) => FocusNode(debugLabel: 'recovery-word-${index + 1}'),
    );
    // Hydrate on attachment as well as updates: the ViewModel can outlive a
    // temporarily unmounted page while retaining a validated phrase.
    ref.listenManual(importWalletViewModelProvider, (_, next) {
      final words = next.value?.words;
      if (words == null) return;
      for (var index = 0; index < words.length; index += 1) {
        if (_controllers[index].text == words[index]) continue;
        _controllers[index].value = TextEditingValue(
          text: words[index],
          selection: TextSelection.collapsed(offset: words[index].length),
        );
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.clear();
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(importWalletViewModelProvider);
    final value = asyncState.value;
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          final navigationLocked =
              navigation.inFlight ||
              (value != null &&
                  (value.submitting || value.requiresReconciliation));
          return PopScope(
            canPop: !navigationLocked,
            child: Scaffold(
              backgroundColor: context.colorScheme.surface,
              resizeToAvoidBottomInset: true,
              body: SafeArea(
                child: switch (asyncState) {
                  AsyncData<ImportWalletState>(:final value) => _buildContent(
                    value,
                    navigation,
                  ),
                  AsyncError<ImportWalletState>(
                    :final error,
                    :final stackTrace,
                  ) =>
                    _buildFailure(navigation, error, stackTrace),
                  _ => const OnboardingStatusPanel.loading(),
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFailure(
    AsterNavigationCommandOwner navigation,
    Object error,
    StackTrace stackTrace,
  ) {
    final failure = FailureMapper.from(error, stackTrace);
    return OnboardingStatusPanel.failure(
      title: 'Recovery phrase unavailable',
      message: failure.userMessage,
      primaryLabel: failure.retryable ? 'Retry' : null,
      onPrimary: failure.retryable
          ? () => ref.invalidate(importWalletViewModelProvider)
          : null,
      onBack: () => _navigateToWelcome(context, navigation),
    );
  }

  Widget _buildContent(
    ImportWalletState state,
    AsterNavigationCommandOwner navigation,
  ) {
    final context = this.context;
    final spacing = context.spacing;
    final colors = context.appColors;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final wordStyle = context.type.assetValue;
    final scaledLineHeight =
        MediaQuery.textScalerOf(context).scale(wordStyle.fontSize!) *
        (wordStyle.height ?? 1);
    final wordFieldHeight = math.max(
      context.metrics.minTouchTarget,
      scaledLineHeight + spacing.lg,
    );

    return AsterFormBody(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.xxl,
              keyboardVisible ? spacing.md : spacing.xxl,
              spacing.xxl,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!keyboardVisible) ...[
                  const OnboardingWelcomeHeader(),
                  SizedBox(height: spacing.huge),
                ],
                Text(
                  'Import with recovery phrase',
                  style: context.type.brandHero.copyWith(
                    color: context.colorScheme.onSurface,
                  ),
                ),
                if (!keyboardVisible) ...[
                  SizedBox(height: spacing.md),
                  Text(
                    'Enter your 12-word recovery phrase in order.',
                    style: context.type.brandBody.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                SizedBox(height: keyboardVisible ? spacing.lg : spacing.xxxl),
              ],
            ),
          ),
          SizedBox(
            height:
                wordFieldHeight * ImportWalletState.wordsPerPage +
                spacing.md * (ImportWalletState.wordsPerPage - 1),
            child: PageView.builder(
              controller: _pageController,
              physics:
                  state.submitting ||
                      state.requiresReconciliation ||
                      navigation.inFlight
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount:
                  ImportWalletState.wordCount ~/ ImportWalletState.wordsPerPage,
              onPageChanged: (page) => setState(() => _currentPage = page),
              itemBuilder: (context, pageIndex) {
                final start = pageIndex * ImportWalletState.wordsPerPage;
                final end = start + ImportWalletState.wordsPerPage;
                return Center(
                  child: OnboardingImportWalletWordPage(
                    controllers: _controllers.sublist(start, end),
                    focusNodes: _focusNodes.sublist(start, end),
                    statuses: state.wordStatuses.sublist(start, end),
                    startIndex: start,
                    fieldHeight: wordFieldHeight,
                    enabled:
                        !state.submitting &&
                        !state.requiresReconciliation &&
                        !navigation.inFlight,
                    canSubmit: state.canContinue,
                    onChanged: _handleWordInput,
                    onSubmitted: (index) =>
                        unawaited(_handleSubmitted(index, state, navigation)),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: spacing.xxl),
          Semantics(
            container: true,
            label: 'Recovery phrase page',
            value:
                '${_currentPage + 1} of '
                '${ImportWalletState.wordCount ~/ ImportWalletState.wordsPerPage}',
            child: ExcludeSemantics(
              child: Center(
                child: SmoothPageIndicator(
                  controller: _pageController,
                  count:
                      ImportWalletState.wordCount ~/
                      ImportWalletState.wordsPerPage,
                  effect: ExpandingDotsEffect(
                    activeDotColor: context.colorScheme.primary,
                    dotColor: colors.borderSubtle,
                    dotHeight: spacing.sm,
                    dotWidth: spacing.sm,
                    expansionFactor:
                        context.art.onboardingIndicatorExpansionFactor,
                    spacing: spacing.sm,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        _PhraseStatus(
          state: state,
          onRetry:
              state.checksumStatus == MnemonicChecksumStatus.incomplete &&
                  state.failure?.retryable == true &&
                  !navigation.inFlight
              ? () => unawaited(
                  ref
                      .read(importWalletViewModelProvider.notifier)
                      .retryChecksum(),
                )
              : null,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.xxl,
            spacing.sm,
            spacing.xxl,
            spacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomButton(
                text: 'Continue',
                variant: ButtonVariant.primary,
                enabled: state.canContinue && !navigation.inFlight,
                hapticIntent: null,
                onTap: () => _openName(navigation),
              ),
              OnboardingTextAction(
                label: 'Back',
                enabled:
                    !state.submitting &&
                    !state.requiresReconciliation &&
                    !navigation.inFlight,
                hapticIntent: null,
                onPressed: () => _navigateToWelcome(context, navigation),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleWordInput(int index, String input) {
    final words = input
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final notifier = ref.read(importWalletViewModelProvider.notifier);
    if (words.length <= 1) {
      notifier.updateWord(index, input);
      return;
    }
    notifier.updateWords(index, words);
    unawaited(_focusAfterPaste(index, words.length));
  }

  Future<void> _focusAfterPaste(int startIndex, int pastedWordCount) async {
    final lastPasted = math.min(
      ImportWalletState.wordCount - 1,
      startIndex + pastedWordCount - 1,
    );
    final next = math.min(ImportWalletState.wordCount - 1, lastPasted + 1);
    await _showPage(next ~/ ImportWalletState.wordsPerPage);
    if (mounted) _focusNodes[next].requestFocus();
  }

  Future<void> _handleSubmitted(
    int index,
    ImportWalletState state,
    AsterNavigationCommandOwner navigation,
  ) async {
    if (state.submitting ||
        state.requiresReconciliation ||
        navigation.inFlight) {
      return;
    }
    if (index == ImportWalletState.wordCount - 1) {
      if (state.canContinue) {
        FocusScope.of(context).unfocus();
        _openName(navigation);
      }
      return;
    }
    final next = index + 1;
    if (next % ImportWalletState.wordsPerPage == 0) {
      await _showPage(next ~/ ImportWalletState.wordsPerPage);
    }
    if (mounted) _focusNodes[next].requestFocus();
  }

  Future<void> _showPage(int page) async {
    if (!_pageController.hasClients || _pageController.page?.round() == page) {
      return;
    }
    final duration = context.motionPolicy.duration(
      context.motion.selectionTransitionDuration,
    );
    if (duration == Duration.zero) {
      _pageController.jumpToPage(page);
      return;
    }
    await _pageController.animateToPage(
      page,
      duration: duration,
      curve: context.motion.choreographyCurve,
    );
  }

  void _openName(AsterNavigationCommandOwner navigation) {
    FocusScope.of(context).unfocus();
    unawaited(
      navigation.openRoute(
        command: () =>
            context.pushNamed<void>(RouteNames.onboardingImportWalletName),
        failureTitle: 'Wallet name screen could not open',
      ),
    );
  }
}

void _navigateToWelcome(
  BuildContext context,
  AsterNavigationCommandOwner navigation,
) {
  unawaited(
    navigation.run(
      command: () => _returnToWelcome(context),
      failureTitle: 'Welcome screen could not open',
    ),
  );
}

void _returnToWelcome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(RoutePaths.onboardingWelcome);
  }
}

class _PhraseStatus extends StatelessWidget {
  const _PhraseStatus({required this.state, this.onRetry});

  final ImportWalletState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (message, color) = switch (state.checksumStatus) {
      _ when state.failure != null => (
        state.failure!.userMessage,
        context.appColors.statusForeground,
      ),
      MnemonicChecksumStatus.checking => (
        'Checking recovery phrase...',
        context.appColors.textSecondary,
      ),
      MnemonicChecksumStatus.valid => (
        'Recovery phrase is valid',
        context.colorScheme.onSurface,
      ),
      MnemonicChecksumStatus.invalid => (
        'The phrase checksum does not match',
        context.appColors.statusForeground,
      ),
      _ => (
        'Never share your recovery phrase',
        context.appColors.textSecondary,
      ),
    };
    return Semantics(
      liveRegion:
          state.checksumStatus != MnemonicChecksumStatus.incomplete ||
          state.failure != null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          context.spacing.xxl,
          context.spacing.md,
          context.spacing.xxl,
          0,
        ),
        child: Column(
          children: [
            Text(
              message,
              style: context.type.brandBody.copyWith(color: color),
              textAlign: TextAlign.center,
            ),
            if (onRetry case final retry?)
              OnboardingTextAction(
                label: 'Retry phrase check',
                onPressed: retry,
              ),
          ],
        ),
      ),
    );
  }
}

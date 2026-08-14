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
    ref.listen(importWalletViewModelProvider, (_, next) {
      final words = next.value?.words;
      if (words == null) return;
      for (var index = 0; index < words.length; index += 1) {
        if (_controllers[index].text == words[index]) continue;
        _controllers[index].value = TextEditingValue(
          text: words[index],
          selection: TextSelection.collapsed(offset: words[index].length),
        );
      }
    });
    final submitting = asyncState.value?.submitting ?? false;

    return PopScope(
      canPop: !submitting,
      child: Scaffold(
        backgroundColor: context.appColors.transparentSurface,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: switch (asyncState) {
            AsyncData<ImportWalletState>(:final value) => _buildContent(value),
            AsyncError<ImportWalletState>(:final error, :final stackTrace) =>
              _buildFailure(error, stackTrace),
            _ => const OnboardingStatusPanel.loading(),
          },
        ),
      ),
    );
  }

  Widget _buildFailure(Object error, StackTrace stackTrace) {
    final failure = FailureMapper.from(error, stackTrace);
    return OnboardingStatusPanel.failure(
      title: 'Recovery phrase unavailable',
      message: failure.userMessage,
      primaryLabel: failure.retryable ? 'Retry' : null,
      onPrimary: failure.retryable
          ? () => ref.invalidate(importWalletViewModelProvider)
          : null,
      onBack: () => _returnToWelcome(context),
    );
  }

  Widget _buildContent(ImportWalletState state) {
    final context = this.context;
    final spacing = context.spacing;
    final colors = context.appColors;
    final effects = context.effects;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final wordStyle = context.type.assetValue;
    final scaledLineHeight =
        MediaQuery.textScalerOf(context).scale(wordStyle.fontSize!) *
        (wordStyle.height ?? 1);
    final wordFieldHeight = math.max(
      context.metrics.minTouchTarget,
      scaledLineHeight + spacing.lg,
    );

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  style: context.type.brandHero,
                ),
                if (!keyboardVisible) ...[
                  SizedBox(height: spacing.md),
                  Text(
                    'Enter your 12-word recovery phrase in order.',
                    style: context.type.brandBody.copyWith(
                      color: colors.onBrandArt.withValues(
                        alpha: effects.brandContentStrongOpacity,
                      ),
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
              physics: state.submitting
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
                    enabled: !state.submitting,
                    canSubmit: state.canSubmit,
                    onChanged: _handleWordInput,
                    onSubmitted: (index) =>
                        unawaited(_handleSubmitted(index, state)),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: spacing.sm),
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
                    activeDotColor: colors.onBrandArt,
                    dotColor: colors.onBrandArt.withValues(
                      alpha: effects.brandIndicatorInactiveOpacity,
                    ),
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
          _PhraseStatus(
            state: state,
            onRetry:
                state.checksumStatus == MnemonicChecksumStatus.incomplete &&
                    state.failure?.retryable == true
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
                  variant: ButtonVariant.translucent,
                  enabled: state.canSubmit,
                  loading: state.submitting,
                  hapticIntent: null,
                  onTap: () => unawaited(_submit()),
                ),
                OnboardingTextAction(
                  label: 'Back',
                  enabled: !state.submitting,
                  onPressed: () => _returnToWelcome(context),
                ),
              ],
            ),
          ),
        ],
      ),
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

  Future<void> _handleSubmitted(int index, ImportWalletState state) async {
    if (state.submitting) return;
    if (index == ImportWalletState.wordCount - 1) {
      if (state.canSubmit) {
        FocusScope.of(context).unfocus();
        await _submit();
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await ref.read(importWalletViewModelProvider.notifier).submit();
  }
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
        context.appColors.danger,
      ),
      MnemonicChecksumStatus.checking => (
        'Checking recovery phrase...',
        context.appColors.onBrandArt,
      ),
      MnemonicChecksumStatus.valid => (
        'Recovery phrase is valid',
        context.appColors.success,
      ),
      MnemonicChecksumStatus.invalid => (
        'The phrase checksum does not match',
        context.appColors.danger,
      ),
      _ => ('Never share your recovery phrase', context.appColors.onBrandArt),
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

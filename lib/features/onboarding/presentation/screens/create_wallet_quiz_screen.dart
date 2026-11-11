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

/// Confirms the fixed 3rd, 7th, and 11th recovery-phrase words.
class CreateWalletQuizScreen extends ConsumerWidget {
  const CreateWalletQuizScreen({
    super.key,
    this.onBack,
    this.onContinue,
    this.onBrandArt = false,
    this.showNavigationBar = true,
  });

  final VoidCallback? onBack;
  final VoidCallback? onContinue;

  /// Whether this step is presented over the retained onboarding artwork.
  final bool onBrandArt;

  /// Whether this standalone screen owns its visible back navigation.
  final bool showNavigationBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(createWalletViewModelProvider);
    final value = asyncState.value;
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          final locked =
              navigation.inFlight ||
              value?.submitting == true ||
              value?.requiresReconciliation == true;
          return PopScope(
            canPop: !locked,
            child: Scaffold(
              backgroundColor: onBrandArt
                  ? context.appColors.transparentSurface
                  : context.colorScheme.surface,
              body: switch (asyncState) {
                AsyncData<CreateWalletState>(:final value)
                    when !value.completed =>
                  OnboardingScrollSafeArea(
                    builder: (_, scrollBottomInset) => _QuizContent(
                      state: value,
                      navigation: navigation,
                      onBack: onBack,
                      onContinue: onContinue,
                      onBrandArt: onBrandArt,
                      showNavigationBar: showNavigationBar,
                      scrollBottomInset: scrollBottomInset,
                    ),
                  ),
                AsyncError<CreateWalletState>(
                  :final error,
                  :final stackTrace,
                ) =>
                  SafeArea(
                    child: _QuizFailure(
                      error: error,
                      stackTrace: stackTrace,
                      onBack: onBack,
                      onBrandArt: onBrandArt,
                      showNavigationBar: showNavigationBar,
                    ),
                  ),
                _ => SafeArea(
                  child: OnboardingStatusPanel.loading(
                    message: 'Preparing recovery check...',
                    onBrandArt: onBrandArt,
                  ),
                ),
              },
            ),
          );
        },
      ),
    );
  }
}

class _QuizContent extends ConsumerWidget {
  const _QuizContent({
    required this.state,
    required this.navigation,
    required this.onBack,
    required this.onContinue,
    required this.onBrandArt,
    required this.showNavigationBar,
    required this.scrollBottomInset,
  });

  final CreateWalletState state;
  final AsterNavigationCommandOwner navigation;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;
  final bool onBrandArt;
  final bool showNavigationBar;
  final double scrollBottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final canNavigateBack =
        !state.submitting &&
        !state.requiresReconciliation &&
        !navigation.inFlight;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: context.metrics.appBarHeight,
            child: showNavigationBar
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: AsterIconButton(
                      icon: MingCuteIcons.mgc_left_line,
                      tooltip: 'Back',
                      onPressed: canNavigateBack
                          ? onBack ?? () => _goBack(context)
                          : null,
                      color: onBrandArt ? colors.onBrandArt : null,
                      hapticIntent: null,
                      alignment: Alignment.centerRight,
                    ),
                  )
                : null,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OnboardingChoreographyItem(
                  id: 'create-quiz-copy-motion',
                  visualIndex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verify seed phrase',
                        style: context.type.pageTitle.copyWith(
                          color: onBrandArt ? colors.onBrandArt : null,
                        ),
                      ),
                      SizedBox(height: spacing.sm),
                      Text(
                        'Choose each word from the recovery phrase you wrote down.',
                        style: context.type.rowMeta.copyWith(
                          color: onBrandArt
                              ? colors.onBrandArt.withValues(
                                  alpha:
                                      context.effects.brandContentStrongOpacity,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.xxl),
                OnboardingChoreographyItem(
                  id: 'create-quiz-question-motion',
                  visualIndex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (
                        var index = 0;
                        index < state.questions.length;
                        index += 1
                      ) ...[
                        _QuizPrompt(
                          question: state.questions[index],
                          selectedOption: state.selectedOptionFor(
                            state.questions[index].wordNumber,
                          ),
                          enabled: !navigation.inFlight,
                          onBrandArt: onBrandArt,
                          onSelected: (word) => ref
                              .read(createWalletViewModelProvider.notifier)
                              .selectQuizOption(
                                wordNumber: state.questions[index].wordNumber,
                                word: word,
                              ),
                        ),
                        if (index < state.questions.length - 1)
                          SizedBox(height: spacing.xl),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.screenPadding,
              0,
              spacing.screenPadding,
              spacing.lg + scrollBottomInset,
            ),
            child: OnboardingChoreographyItem(
              id: 'create-quiz-actions-motion',
              visualIndex: 3,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: CustomButton(
                  text: 'Continue',
                  variant: onBrandArt
                      ? ButtonVariant.translucent
                      : ButtonVariant.primary,
                  enabled: state.quizComplete && !navigation.inFlight,
                  hapticIntent: null,
                  onTap: _openName,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openName() {
    if (onContinue case final callback?) {
      callback();
      return;
    }
    throw StateError('Wallet setup must provide an in-place name callback.');
  }

  void _goBack(BuildContext context) {
    unawaited(
      navigation.run(
        command: () => context.pop(),
        failureTitle: 'Recovery phrase screen could not open',
      ),
    );
  }
}

class _QuizPrompt extends StatelessWidget {
  const _QuizPrompt({
    required this.question,
    required this.selectedOption,
    required this.enabled,
    required this.onBrandArt,
    required this.onSelected,
  });

  final RecoveryPhraseQuestion question;
  final String? selectedOption;
  final bool enabled;
  final bool onBrandArt;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final confirmed = selectedOption == question.expectedWord;
    return Column(
      key: ValueKey('quiz-row-${question.wordNumber}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NumericText(
          'Word ${question.wordNumber}',
          style: context.type.sectionLabel.copyWith(
            color: onBrandArt ? context.appColors.onBrandArt : null,
          ),
        ),
        // The visible tile is vertically centered in a 48 px hit target.
        // Two layout pixels plus that inset produce an 8 px visual gap.
        SizedBox(height: spacing.xxs),
        Row(
          children: [
            for (
              var index = 0;
              index < question.options.length;
              index += 1
            ) ...[
              Expanded(
                child: _QuizOption(
                  wordNumber: question.wordNumber,
                  word: question.options[index],
                  status: switch (question.options[index]) {
                    final word when word != selectedOption =>
                      _QuizOptionStatus.idle,
                    final word when word == question.expectedWord =>
                      _QuizOptionStatus.correct,
                    _ => _QuizOptionStatus.incorrect,
                  },
                  onBrandArt: onBrandArt,
                  onTap: enabled && !confirmed
                      ? () => onSelected(question.options[index])
                      : null,
                ),
              ),
              if (index < question.options.length - 1)
                SizedBox(width: spacing.sm),
            ],
          ],
        ),
      ],
    );
  }
}

enum _QuizOptionStatus { idle, correct, incorrect }

class _QuizOption extends StatelessWidget {
  const _QuizOption({
    required this.wordNumber,
    required this.word,
    required this.status,
    required this.onBrandArt,
    required this.onTap,
  });

  final int wordNumber;
  final String word;
  final _QuizOptionStatus status;
  final bool onBrandArt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final surface = onBrandArt
        ? context.colorScheme.surface.withValues(
            alpha: context.stateLayers.translucentSurface,
          )
        : colors.surfaceSubtle;
    final border = onBrandArt
        ? colors.onBrandArt.withValues(
            alpha: context.effects.brandGlassBorderOpacity,
          )
        : colors.borderSubtle;
    final statusProgress = switch (status) {
      _QuizOptionStatus.idle => 0.0,
      _QuizOptionStatus.correct => 1.0,
      _QuizOptionStatus.incorrect => -1.0,
    };
    final statusLabel = switch (status) {
      _QuizOptionStatus.idle => null,
      _QuizOptionStatus.correct => 'Correct',
      _QuizOptionStatus.incorrect => 'Incorrect',
    };
    final duration = context.motionPolicy.duration(
      context.motion.selectionTransitionDuration,
    );
    return Semantics(
      key: ValueKey('quiz-option-$wordNumber-$word'),
      button: true,
      enabled: onTap != null,
      label: word,
      value: statusLabel,
      selected: status != _QuizOptionStatus.idle,
      liveRegion: status != _QuizOptionStatus.idle,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        height: context.metrics.minTouchTarget,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Align(
            child: SizedBox(
              width: double.infinity,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: statusProgress),
                duration: duration,
                curve: context.motion.fastEase,
                builder: (context, progress, child) {
                  final statusColor = progress >= 0
                      ? colors.success
                      : colors.danger;
                  final statusContainer = progress >= 0
                      ? colors.successContainer
                      : colors.dangerContainer;
                  final emphasis = progress.abs();
                  return Squircle(
                    key: ValueKey('quiz-option-surface-$wordNumber-$word'),
                    padding: EdgeInsets.symmetric(
                      horizontal: context.spacing.md,
                      vertical: context.spacing.sm,
                    ),
                    borderRadius: context.radii.recoveryWord,
                    color: Color.lerp(surface, statusContainer, emphasis),
                    borderColor: Color.lerp(border, statusColor, emphasis),
                    borderWidth: context.strokes.hairline,
                    child: Text(
                      word,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: context.type.rowTitle.copyWith(
                        color: Color.lerp(
                          context.type.rowTitle.color,
                          colors.statusForeground,
                          emphasis,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuizFailure extends StatelessWidget {
  const _QuizFailure({
    required this.error,
    required this.stackTrace,
    required this.onBack,
    required this.onBrandArt,
    required this.showNavigationBar,
  });

  final Object error;
  final StackTrace stackTrace;
  final VoidCallback? onBack;
  final bool onBrandArt;
  final bool showNavigationBar;

  @override
  Widget build(BuildContext context) {
    final failure = FailureMapper.from(error, stackTrace);
    return OnboardingStatusPanel.failure(
      title: 'Recovery check unavailable',
      message: failure.userMessage,
      onBack: showNavigationBar ? onBack ?? () => context.pop() : null,
      onBrandArt: onBrandArt,
    );
  }
}

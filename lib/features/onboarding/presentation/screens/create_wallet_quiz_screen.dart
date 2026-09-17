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

/// Confirms the fixed 3rd, 6th, 9th, and 12th recovery-phrase words.
class CreateWalletQuizScreen extends ConsumerWidget {
  const CreateWalletQuizScreen({
    super.key,
    this.origin = WalletCreationOrigin.onboarding,
  });

  final WalletCreationOrigin origin;

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
              backgroundColor: context.colorScheme.surface,
              body: SafeArea(
                child: switch (asyncState) {
                  AsyncData<CreateWalletState>(:final value)
                      when !value.completed =>
                    _QuizContent(
                      state: value,
                      origin: origin,
                      navigation: navigation,
                    ),
                  AsyncError<CreateWalletState>(
                    :final error,
                    :final stackTrace,
                  ) =>
                    _QuizFailure(error: error, stackTrace: stackTrace),
                  _ => const OnboardingStatusPanel.loading(
                    message: 'Preparing recovery check...',
                  ),
                },
              ),
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
    required this.origin,
    required this.navigation,
  });

  final CreateWalletState state;
  final WalletCreationOrigin origin;
  final AsterNavigationCommandOwner navigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final question = state.currentQuestion;
    final canNavigateBack =
        !state.submitting &&
        !state.requiresReconciliation &&
        !navigation.inFlight;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: context.metrics.appBarHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AsterIconButton(
                icon: MingCuteIcons.mgc_left_line,
                tooltip: 'Back',
                onPressed: canNavigateBack ? () => _goBack(context) : null,
                hapticIntent: null,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Check your backup', style: context.type.pageTitle),
                SizedBox(height: spacing.sm),
                Text(
                  'Choose each word from the recovery phrase you wrote down.',
                  style: context.type.rowMeta,
                ),
                SizedBox(height: spacing.xxl),
                if (question case final prompt?) ...[
                  NumericText(
                    'Word ${prompt.wordNumber} of ${CreateWalletState.wordCount}',
                    style: context.type.sectionLabel,
                  ),
                  SizedBox(height: spacing.md),
                  _QuizOptions(
                    question: prompt,
                    rejectedOption: state.rejectedQuizOption,
                    enabled: !navigation.inFlight,
                    onSelected: (word) => ref
                        .read(createWalletViewModelProvider.notifier)
                        .selectQuizOption(word),
                  ),
                  if (state.rejectedQuizOption != null) ...[
                    SizedBox(height: spacing.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'That is not word ${prompt.wordNumber}. Check your backup and try again.',
                        style: context.type.errorMessage,
                      ),
                    ),
                  ],
                ] else
                  _QuizComplete(),
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
              spacing.lg,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomButton(
                  text: 'Continue',
                  enabled: state.quizComplete && !navigation.inFlight,
                  hapticIntent: null,
                  onTap: () => _openName(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openName(BuildContext context) {
    unawaited(_openNameAndForwardResult(context));
  }

  Future<void> _openNameAndForwardResult(BuildContext context) async {
    final routeName = switch (origin) {
      WalletCreationOrigin.onboarding => RouteNames.onboardingCreateWalletName,
      WalletCreationOrigin.walletSelector => RouteNames.addWalletName,
    };
    final outcome = await navigation
        .openRouteForResult<WalletCreationRouteResult>(
          command: () =>
              context.pushNamed<WalletCreationRouteResult>(routeName),
          failureTitle: 'Wallet name screen could not open',
        );
    if (!outcome.accepted ||
        outcome.value != WalletCreationRouteResult.created ||
        origin != WalletCreationOrigin.walletSelector ||
        !context.mounted) {
      return;
    }
    context.pop(WalletCreationRouteResult.created);
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

class _QuizOptions extends StatelessWidget {
  const _QuizOptions({
    required this.question,
    required this.rejectedOption,
    required this.enabled,
    required this.onSelected,
  });

  final RecoveryPhraseQuestion question;
  final String? rejectedOption;
  final bool enabled;
  final ValueChanged<String> onSelected;

  static const _columnCount = 2;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final rowCount = question.options.length ~/ _columnCount;
    return Column(
      children: List.generate(rowCount, (row) {
        return Padding(
          padding: EdgeInsets.only(bottom: row < rowCount - 1 ? spacing.sm : 0),
          child: Row(
            children: List.generate(_columnCount, (column) {
              final index = row * _columnCount + column;
              final word = question.options[index];
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: column < _columnCount - 1 ? spacing.sm : 0,
                  ),
                  child: _QuizOption(
                    word: word,
                    rejected: rejectedOption == word,
                    onTap: enabled ? () => onSelected(word) : null,
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _QuizOption extends StatelessWidget {
  const _QuizOption({
    required this.word,
    required this.rejected,
    required this.onTap,
  });

  final String word;
  final bool rejected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final trailing = rejected
        ? Icon(
            Icons.close_rounded,
            size: context.icons.xs,
            color: colors.danger,
          )
        : const AsterSelectionIndicator(selected: false);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: word,
      value: rejected ? 'Incorrect' : null,
      onTap: onTap,
      excludeSemantics: true,
      child: Squircle(
        padding: EdgeInsets.zero,
        borderRadius: context.radii.recoveryWord,
        color: rejected ? colors.dangerContainer : colors.surfaceSubtle,
        borderColor: rejected ? colors.danger : colors.borderSubtle,
        borderWidth: context.strokes.hairline,
        child: Material(
          color: colors.transparentSurface,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: context.metrics.minTouchTarget,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.spacing.md,
                  vertical: context.spacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(word, style: context.type.rowTitle)),
                    SizedBox(width: context.spacing.sm),
                    trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuizComplete extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Recovery phrase confirmed',
      child: Squircle(
        padding: EdgeInsets.all(context.spacing.xl),
        child: Row(
          children: [
            Icon(
              Icons.check_rounded,
              size: context.icons.md,
              color: context.appColors.success,
            ),
            SizedBox(width: context.spacing.md),
            Expanded(
              child: Text(
                'Recovery phrase confirmed',
                style: context.type.rowTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuizFailure extends StatelessWidget {
  const _QuizFailure({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    final failure = FailureMapper.from(error, stackTrace);
    return OnboardingStatusPanel.failure(
      title: 'Recovery check unavailable',
      message: failure.userMessage,
      onBack: () => context.pop(),
    );
  }
}

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

/// Generates and displays a route-owned 12-word recovery phrase.
class OnboardingCreateWalletScreen extends ConsumerWidget {
  const OnboardingCreateWalletScreen({
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
          final navigationLocked =
              navigation.inFlight ||
              (value != null &&
                  (value.submitting || value.requiresReconciliation));
          return PopScope(
            canPop: !navigationLocked,
            child: Scaffold(
              backgroundColor: context.colorScheme.surface,
              body: SafeArea(
                child: switch (asyncState) {
                  AsyncData<CreateWalletState>(:final value)
                      when !value.completed =>
                    _CreateWalletContent(
                      state: value,
                      navigation: navigation,
                      origin: origin,
                    ),
                  AsyncError<CreateWalletState>(
                    :final error,
                    :final stackTrace,
                  ) =>
                    _buildFailure(context, ref, navigation, error, stackTrace),
                  _ => const OnboardingStatusPanel.loading(
                    message: 'Generating your recovery phrase...',
                  ),
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFailure(
    BuildContext context,
    WidgetRef ref,
    AsterNavigationCommandOwner navigation,
    Object error,
    StackTrace stackTrace,
  ) {
    final failure = FailureMapper.from(error, stackTrace);
    return OnboardingStatusPanel.failure(
      title: 'Wallet could not be prepared',
      message: failure.userMessage,
      primaryLabel: failure.retryable ? 'Retry' : null,
      onPrimary: failure.retryable
          ? () => ref.invalidate(createWalletViewModelProvider)
          : null,
      onBack: () => _navigateBack(context, navigation, origin),
    );
  }
}

class _CreateWalletContent extends ConsumerStatefulWidget {
  const _CreateWalletContent({
    required this.state,
    required this.navigation,
    required this.origin,
  });

  final CreateWalletState state;
  final AsterNavigationCommandOwner navigation;
  final WalletCreationOrigin origin;

  @override
  ConsumerState<_CreateWalletContent> createState() =>
      _CreateWalletContentState();
}

class _CreateWalletContentState extends ConsumerState<_CreateWalletContent>
    with WidgetsBindingObserver {
  bool _phraseRevealed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _concealPhrase();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final state = widget.state;
    final navigation = widget.navigation;
    final canNavigateBack =
        !state.submitting &&
        !state.requiresReconciliation &&
        !navigation.inFlight;
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: context.metrics.appBarHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AsterIconButton(
                icon: MingCuteIcons.mgc_left_line,
                tooltip: 'Back',
                onPressed: canNavigateBack
                    ? () => _navigateBack(context, navigation, widget.origin)
                    : null,
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
                Text(
                  'Your 12-word recovery phrase',
                  style: context.type.pageTitle,
                ),
                SizedBox(height: spacing.sm),
                Text(
                  'Keep this offline and never share it with anyone.',
                  style: context.type.rowMeta,
                ),
                SizedBox(height: spacing.xxl),
                OnboardingImportWalletWordGrid(
                  words: state.words,
                  obscured: !_phraseRevealed,
                ),
                SizedBox(height: spacing.xs),
                Center(
                  child: OnboardingTextAction(
                    label: 'Copy recovery phrase',
                    icon: MingCuteIcons.mgc_copy_2_line,
                    size: OnboardingTextActionSize.compact,
                    enabled: state.canCopy && !navigation.inFlight,
                    loading: state.copying,
                    hapticIntent: null,
                    onPressed: () => unawaited(_copy(context, ref)),
                  ),
                ),
                if (state.failure case final failure?) ...[
                  SizedBox(height: spacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      failure.userMessage,
                      style: context.type.errorMessage.copyWith(
                        color: context.appColors.statusForeground,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
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
                  variant: ButtonVariant.primary,
                  enabled:
                      state.canCopy &&
                      !state.requiresReconciliation &&
                      !navigation.inFlight,
                  hapticIntent: null,
                  onTap: () => _openQuiz(context),
                ),
                SizedBox(height: spacing.md),
                CustomButton(
                  text: _phraseRevealed ? 'Hide phrase' : 'Reveal phrase',
                  prefixIcon: _phraseRevealed
                      ? MingCuteIcons.mgc_eye_close_line
                      : MingCuteIcons.mgc_eye_2_line,
                  variant: ButtonVariant.secondary,
                  enabled: !state.submitting && !widget.navigation.inFlight,
                  onTap: _togglePhraseVisibility,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(createWalletViewModelProvider.notifier)
        .copyMnemonic();
    if (!context.mounted) return;
    switch (result) {
      case AppSuccess<void>():
        context.toasts.show(
          title: 'Recovery phrase copied',
          message: 'It will be cleared from the clipboard after one minute.',
          variant: ToastVariant.success,
        );
      case AppFailureResult<void>(:final failure):
        context.toasts.show(
          title: 'Could not copy recovery phrase',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
    }
  }

  void _openQuiz(BuildContext context) {
    _concealPhrase();
    unawaited(_openQuizAndForwardResult(context));
  }

  Future<void> _openQuizAndForwardResult(BuildContext context) async {
    final routeName = switch (widget.origin) {
      WalletCreationOrigin.onboarding => RouteNames.onboardingCreateWalletQuiz,
      WalletCreationOrigin.walletSelector => RouteNames.addWalletQuiz,
    };
    final outcome = await widget.navigation
        .openRouteForResult<WalletCreationRouteResult>(
          command: () =>
              context.pushNamed<WalletCreationRouteResult>(routeName),
          failureTitle: 'Recovery check could not open',
        );
    if (!outcome.accepted ||
        outcome.value != WalletCreationRouteResult.created ||
        widget.origin != WalletCreationOrigin.walletSelector ||
        !context.mounted) {
      return;
    }
    context.pop(WalletCreationRouteResult.created);
  }

  void _togglePhraseVisibility() {
    setState(() => _phraseRevealed = !_phraseRevealed);
  }

  void _concealPhrase() {
    if (!_phraseRevealed || !mounted) return;
    setState(() => _phraseRevealed = false);
  }
}

void _navigateBack(
  BuildContext context,
  AsterNavigationCommandOwner navigation,
  WalletCreationOrigin origin,
) {
  unawaited(
    navigation.run(
      command: () => _returnToPrevious(context, origin),
      failureTitle: 'Previous screen could not open',
    ),
  );
}

void _returnToPrevious(BuildContext context, WalletCreationOrigin origin) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(switch (origin) {
      WalletCreationOrigin.onboarding => RoutePaths.onboardingWelcome,
      WalletCreationOrigin.walletSelector => RoutePaths.walletSelectionLocation,
    });
  }
}

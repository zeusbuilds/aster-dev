import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Displays the recovery phrase prepared by the wallet setup journey.
class OnboardingCreateWalletScreen extends ConsumerWidget {
  const OnboardingCreateWalletScreen({
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
  ///
  /// The single-route journey disables this and paints one retained top bar
  /// above every animated step instead.
  final bool showNavigationBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(createWalletViewModelProvider);
    final state = asyncState.asData?.value;
    if (asyncState.isLoading || state == null || state.completed) {
      return const SizedBox.shrink();
    }
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          final navigationLocked =
              navigation.inFlight ||
              state.submitting ||
              state.requiresReconciliation;
          return PopScope(
            canPop: !navigationLocked,
            child: Scaffold(
              backgroundColor: onBrandArt
                  ? context.appColors.transparentSurface
                  : context.colorScheme.surface,
              body: OnboardingScrollSafeArea(
                builder: (_, scrollBottomInset) => _CreateWalletContent(
                  state: state,
                  navigation: navigation,
                  onBack: onBack,
                  onContinue: onContinue,
                  onBrandArt: onBrandArt,
                  showNavigationBar: showNavigationBar,
                  scrollBottomInset: scrollBottomInset,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CreateWalletContent extends ConsumerStatefulWidget {
  const _CreateWalletContent({
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
    final colors = context.appColors;
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
            child: widget.showNavigationBar
                ? Row(
                    children: [
                      AsterIconButton(
                        icon: MingCuteIcons.mgc_left_line,
                        tooltip: 'Back',
                        onPressed: canNavigateBack
                            ? widget.onBack ??
                                  () => _navigateBack(context, navigation)
                            : null,
                        color: widget.onBrandArt ? colors.onBrandArt : null,
                        hapticIntent: null,
                        alignment: Alignment.centerRight,
                      ),
                    ],
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
                  id: 'create-recovery-copy-motion',
                  visualIndex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your 12-word recovery phrase',
                        style: context.type.pageTitle.copyWith(
                          color: widget.onBrandArt ? colors.onBrandArt : null,
                        ),
                      ),
                      SizedBox(height: spacing.sm),
                      Text(
                        'Keep this offline and never share it with anyone.',
                        style: context.type.rowMeta.copyWith(
                          color: widget.onBrandArt
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
                  id: 'create-recovery-phrase-motion',
                  visualIndex: 2,
                  child: Column(
                    children: [
                      OnboardingRecoveryPhraseGrid(
                        words: state.words,
                        obscured: !_phraseRevealed,
                        onBrandArt: widget.onBrandArt,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OnboardingTextAction(
                          label: _phraseRevealed ? 'Hide' : 'Reveal',
                          icon: _phraseRevealed
                              ? MingCuteIcons.mgc_eye_close_line
                              : MingCuteIcons.mgc_eye_2_line,
                          enabled: !state.submitting && !navigation.inFlight,
                          onBrandArt: widget.onBrandArt,
                          size: OnboardingTextActionSize.compact,
                          onPressed: _togglePhraseVisibility,
                        ),
                      ),
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
              spacing.lg + widget.scrollBottomInset,
            ),
            child: OnboardingChoreographyItem(
              id: 'create-recovery-actions-motion',
              visualIndex: 3,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: CustomButton(
                  text: 'Continue',
                  variant: ButtonVariant.translucent,
                  enabled:
                      state.canContinue &&
                      !state.requiresReconciliation &&
                      !navigation.inFlight,
                  hapticIntent: null,
                  onTap: _openQuiz,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openQuiz() {
    _concealPhrase();
    if (widget.onContinue case final onContinue?) {
      onContinue();
      return;
    }
    throw StateError(
      'Wallet setup must provide an in-place recovery-check callback.',
    );
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
) {
  unawaited(
    navigation.run(
      command: () => context.pop(),
      failureTitle: 'Previous screen could not open',
    ),
  );
}

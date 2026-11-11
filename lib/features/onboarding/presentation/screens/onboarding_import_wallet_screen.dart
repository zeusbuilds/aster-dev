import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Imports a wallet through 12 per-word fields and SDK checksum validation.
class OnboardingImportWalletScreen extends ConsumerStatefulWidget {
  const OnboardingImportWalletScreen({
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
  ConsumerState<OnboardingImportWalletScreen> createState() =>
      _OnboardingImportWalletScreenState();
}

class _OnboardingImportWalletScreenState
    extends ConsumerState<OnboardingImportWalletScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
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
    ref.listenManual(
      importWalletViewModelProvider,
      _onChecksumResult,
      fireImmediately: false,
    );
  }

  void _onChecksumResult(
    AsyncValue<ImportWalletState>? previous,
    AsyncValue<ImportWalletState> next,
  ) {
    final failedState = next.value;
    final failure = failedState?.failure;
    if (previous?.value?.checksumStatus != MnemonicChecksumStatus.checking ||
        next is! AsyncData<ImportWalletState> ||
        failedState == null ||
        !failedState.allWordsKnown ||
        failedState.checksumStatus != MnemonicChecksumStatus.incomplete ||
        failedState.submitting ||
        failedState.completed ||
        failedState.requiresReconciliation ||
        failure?.retryable != true) {
      return;
    }
    // Report only this newly completed check. A retained failure, an edited
    // phrase, or a departed screen must not replay it as unrelated feedback.
    final toasts = context.toasts;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(
            ref.read(importWalletViewModelProvider).value,
            failedState,
          ) ||
          !(ModalRoute.of(context)?.isCurrent ?? true) ||
          !TickerMode.valuesOf(context).enabled ||
          OnboardingChoreographyScope.maybeOf(context)?.exiting == true ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed)) {
        return;
      }
      toasts.show(
        title: 'Phrase could not be checked',
        message: failure!.userMessage,
        variant: ToastVariant.failure,
      );
    });
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
              backgroundColor: widget.onBrandArt
                  ? context.appColors.transparentSurface
                  : context.colorScheme.surface,
              resizeToAvoidBottomInset: true,
              body: switch (asyncState) {
                AsyncData<ImportWalletState>(:final value) =>
                  OnboardingScrollSafeArea(
                    builder: (_, scrollBottomInset) =>
                        _buildContent(value, navigation, scrollBottomInset),
                  ),
                AsyncError<ImportWalletState>(
                  :final error,
                  :final stackTrace,
                ) =>
                  SafeArea(child: _buildFailure(navigation, error, stackTrace)),
                _ => SafeArea(
                  child: OnboardingStatusPanel.loading(
                    onBrandArt: widget.onBrandArt,
                  ),
                ),
              },
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
      onBack: widget.showNavigationBar
          ? widget.onBack ?? () => _navigateToWelcome(context, navigation)
          : null,
      onBrandArt: widget.onBrandArt,
    );
  }

  Widget _buildContent(
    ImportWalletState state,
    AsterNavigationCommandOwner navigation,
    double scrollBottomInset,
  ) {
    final context = this.context;
    final spacing = context.spacing;
    final colors = context.appColors;
    final canNavigateBack =
        !state.submitting &&
        !state.requiresReconciliation &&
        !navigation.inFlight;
    final canRetryChecksum =
        state.allWordsKnown &&
        state.checksumStatus == MnemonicChecksumStatus.incomplete &&
        state.failure?.retryable == true;

    return AsterFormBody(
      bottomPadding: scrollBottomInset,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: context.metrics.appBarHeight,
            child: widget.showNavigationBar
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: AsterIconButton(
                      icon: MingCuteIcons.mgc_left_line,
                      tooltip: 'Back',
                      onPressed: canNavigateBack
                          ? widget.onBack ??
                                () => _navigateToWelcome(context, navigation)
                          : null,
                      color: widget.onBrandArt ? colors.onBrandArt : null,
                      hapticIntent: null,
                      alignment: Alignment.centerRight,
                    ),
                  )
                : null,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.screenPadding,
              spacing.lg,
              spacing.screenPadding,
              0,
            ),
            child: OnboardingChoreographyItem(
              id: 'import-copy-motion',
              visualIndex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Import with recovery phrase',
                    style: context.type.pageTitle.copyWith(
                      color: widget.onBrandArt ? colors.onBrandArt : null,
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                    'Enter your 12-word recovery phrase in order. '
                    'Never share it with anyone.',
                    style: context.type.rowMeta.copyWith(
                      color: widget.onBrandArt
                          ? colors.onBrandArt.withValues(
                              alpha: context.effects.brandContentStrongOpacity,
                            )
                          : null,
                    ),
                  ),
                  SizedBox(height: spacing.xxl),
                ],
              ),
            ),
          ),
          OnboardingChoreographyItem(
            id: 'import-fields-motion',
            visualIndex: 2,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
              child: OnboardingEditableRecoveryPhraseGrid(
                controllers: _controllers,
                focusNodes: _focusNodes,
                statuses: state.wordStatuses,
                enabled:
                    !state.submitting &&
                    !state.requiresReconciliation &&
                    !navigation.inFlight,
                onBrandArt: widget.onBrandArt,
                onChanged: _handleWordInput,
                onSubmitted: (index) =>
                    unawaited(_handleSubmitted(index, navigation)),
              ),
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.screenPadding,
            spacing.sm,
            spacing.screenPadding,
            spacing.lg,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OnboardingChoreographyItem(
              id: 'import-actions-motion',
              visualIndex: 3,
              child: CustomButton(
                text: 'Continue',
                variant: widget.onBrandArt
                    ? ButtonVariant.translucent
                    : ButtonVariant.primary,
                enabled:
                    (state.canContinue || canRetryChecksum) &&
                    !navigation.inFlight,
                loading: state.checksumStatus == MnemonicChecksumStatus.checking,
                hapticIntent: null,
                onTap: () => unawaited(_continueImport(navigation)),
              ),
            ),
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
    _focusAfterPaste(index, words.length);
  }

  void _focusAfterPaste(int startIndex, int pastedWordCount) {
    final lastPasted = math.min(
      ImportWalletState.wordCount - 1,
      startIndex + pastedWordCount - 1,
    );
    final next = math.min(ImportWalletState.wordCount - 1, lastPasted + 1);
    if (mounted) _focusNodes[next].requestFocus();
  }

  Future<void> _handleSubmitted(
    int index,
    AsterNavigationCommandOwner navigation,
  ) async {
    final state = ref.read(importWalletViewModelProvider).value;
    if (state == null) return;
    if (state.submitting ||
        state.requiresReconciliation ||
        navigation.inFlight) {
      return;
    }
    if (index == ImportWalletState.wordCount - 1) {
      final firstUnreadyWord = state.wordStatuses.indexWhere(
        (status) => status != MnemonicWordStatus.valid,
      );
      if (firstUnreadyWord >= 0) {
        _focusNodes[firstUnreadyWord].requestFocus();
        return;
      }
      await _continueImport(navigation, waitForActiveValidation: true);
      return;
    }
    final next = index + 1;
    if (mounted) _focusNodes[next].requestFocus();
  }

  Future<void> _continueImport(
    AsterNavigationCommandOwner navigation, {
    bool waitForActiveValidation = false,
  }) async {
    if (navigation.inFlight) return;
    var state = ref.read(importWalletViewModelProvider).value;
    if (state == null || state.requiresReconciliation || state.submitting) {
      return;
    }
    FocusScope.of(context).unfocus();

    final notifier = ref.read(importWalletViewModelProvider.notifier);
    if (state.checksumStatus == MnemonicChecksumStatus.checking) {
      if (!waitForActiveValidation) return;
      await notifier.waitForChecksumValidation();
      if (!mounted || navigation.inFlight) return;
      state = ref.read(importWalletViewModelProvider).value;
      if (state == null || state.requiresReconciliation || state.submitting) {
        return;
      }
    }

    final shouldRetryChecksum =
        state.allWordsKnown &&
        state.checksumStatus == MnemonicChecksumStatus.incomplete &&
        state.failure?.retryable == true;
    if (shouldRetryChecksum) {
      await notifier.retryChecksum();
      if (!mounted || navigation.inFlight) return;
      state = ref.read(importWalletViewModelProvider).value;
    }
    if (state?.canContinue == true) _openName();
  }

  void _openName() {
    FocusScope.of(context).unfocus();
    if (widget.onContinue case final onContinue?) {
      onContinue();
      return;
    }
    throw StateError(
      'Initial onboarding must provide an in-place wallet-name callback.',
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

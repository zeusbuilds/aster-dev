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

/// Generates, displays, and provisions a new 12-word wallet.
class OnboardingCreateWalletScreen extends ConsumerWidget {
  const OnboardingCreateWalletScreen({super.key});

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
                    _CreateWalletContent(state: value, navigation: navigation),
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
      onBack: () => _navigateToWelcome(context, navigation),
    );
  }
}

class _CreateWalletContent extends ConsumerWidget {
  const _CreateWalletContent({required this.state, required this.navigation});

  final CreateWalletState state;
  final AsterNavigationCommandOwner navigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
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
                const OnboardingWelcomeHeader(),
                SizedBox(height: spacing.huge),
                Text(
                  'Secure your wallet',
                  style: context.type.brandHero.copyWith(
                    color: context.colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: spacing.md),
                Text(
                  'Write these 12 words down in order. Keep them offline and '
                  'never share them with anyone.',
                  style: context.type.brandBody.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
                SizedBox(height: spacing.xxxl),
                OnboardingImportWalletWordGrid(words: state.words),
                SizedBox(height: spacing.lg),
                Center(
                  child: OnboardingTextAction(
                    label: 'Copy recovery phrase',
                    icon: MingCuteIcons.mgc_copy_2_line,
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
              spacing.xxl,
              0,
              spacing.xxl,
              spacing.lg,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomButton(
                  text: 'Continue',
                  variant: ButtonVariant.primary,
                  enabled: state.canSubmit && !navigation.inFlight,
                  loading: state.submitting,
                  hapticIntent: null,
                  onTap: () => unawaited(_submit(context, ref)),
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

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    await navigation.run(
      command: () => ref.read(createWalletViewModelProvider.notifier).submit(),
      failureTitle: 'Wallet could not be created',
      hapticIntent: null,
      blocksRoutePop: true,
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

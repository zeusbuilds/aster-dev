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
    final submitting = asyncState.value?.submitting ?? false;
    return PopScope(
      canPop: !submitting,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const OnboardingWelcomeMeshBackground(),
            SafeArea(
              child: switch (asyncState) {
                AsyncData<CreateWalletState>(:final value)
                    when !value.completed =>
                  _CreateWalletContent(state: value),
                AsyncError<CreateWalletState>(
                  :final error,
                  :final stackTrace,
                ) =>
                  OnboardingStatusPanel.failure(
                    title: 'Wallet could not be prepared',
                    message: FailureMapper.from(error, stackTrace).userMessage,
                    primaryLabel: 'Retry',
                    onPrimary: () =>
                        ref.invalidate(createWalletViewModelProvider),
                    onBack: () => _returnToWelcome(context),
                  ),
                _ => const OnboardingStatusPanel.loading(
                  message: 'Generating your recovery phrase...',
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateWalletContent extends ConsumerWidget {
  const _CreateWalletContent({required this.state});

  final CreateWalletState state;

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
                Text('Secure your wallet', style: context.type.brandHero),
                SizedBox(height: spacing.md),
                Text(
                  'Write these 12 words down in order. Keep them offline and '
                  'never share them with anyone.',
                  style: context.type.brandBody,
                ),
                SizedBox(height: spacing.xxxl),
                OnboardingImportWalletWordGrid(words: state.words),
                SizedBox(height: spacing.lg),
                CustomButton(
                  text: 'Copy recovery phrase',
                  prefixIcon: MingCuteIcons.mgc_copy_2_line,
                  variant: ButtonVariant.translucent,
                  enabled: !state.submitting,
                  loading: state.copying,
                  hapticIntent: null,
                  onTap: () => unawaited(_copy(context, ref)),
                ),
                if (state.failure case final failure?) ...[
                  SizedBox(height: spacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      failure.userMessage,
                      style: context.type.errorMessage.copyWith(
                        color: context.appColors.danger,
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
                  variant: ButtonVariant.translucent,
                  enabled: state.canSubmit,
                  loading: state.submitting,
                  hapticIntent: null,
                  onTap: () => unawaited(
                    ref.read(createWalletViewModelProvider.notifier).submit(),
                  ),
                ),
                OnboardingTextAction(
                  label: 'Back',
                  enabled: !state.submitting,
                  onPressed: () => _returnToWelcome(context),
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
}

void _returnToWelcome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(RoutePaths.onboardingWelcome);
  }
}

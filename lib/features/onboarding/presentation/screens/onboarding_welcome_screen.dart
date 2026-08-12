import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Onboarding welcome screen with branded hero, mesh background, and CTA.
class OnboardingWelcomeScreen extends StatelessWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.transparentSurface,
      body: const SafeArea(child: _OnboardingContent()),
    );
  }
}

class _OnboardingContent extends StatelessWidget {
  const _OnboardingContent();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final type = context.type;

    return CustomScrollView(
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
                const OnboardingWelcomeIconGrid(),
                SizedBox(height: spacing.xxxl),
                Text('Built for\nUSDT on Bitcoin', style: type.brandHero),
                SizedBox(height: spacing.md),
                Text(
                  'One wallet for Bitcoin and RGB assets across onchain and '
                  'Lightning.',
                  style: type.brandBody,
                ),
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
              spacing.xxl,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomButton(
                  text: 'Create Wallet',
                  variant: ButtonVariant.translucent,
                  onTap: () => context.push(RoutePaths.onboardingCreateWallet),
                ),
                SizedBox(height: spacing.md),
                OnboardingTextAction(
                  label: 'Import Wallet',
                  onPressed: () =>
                      context.push(RoutePaths.onboardingImportWallet),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

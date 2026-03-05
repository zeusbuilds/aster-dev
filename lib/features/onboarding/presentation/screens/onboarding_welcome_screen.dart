import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';
import '../widgets/onboarding_welcome_header.dart';
import '../widgets/onboarding_welcome_icon_grid.dart';
import '../widgets/onboarding_welcome_mesh_background.dart';

/// Onboarding welcome screen with branded hero, mesh background, and CTA.
class OnboardingWelcomeScreen extends StatelessWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const OnboardingWelcomeMeshBackground(),
          const SafeArea(child: _OnboardingContent()),
        ],
      ),
    );
  }
}

class _OnboardingContent extends StatelessWidget {
  const _OnboardingContent();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;
    final textTheme = context.textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.spacing24,
        vertical: spacing.spacing24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnboardingWelcomeHeader(),
          SizedBox(height: spacing.spacing40),
          const OnboardingWelcomeIconGrid(),
          SizedBox(height: spacing.spacing36),
          Text(
            'Built on\norchestration, not\nguesswork.',
            style: textTheme.displaySmall?.copyWith(
              color: colors.text5,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
          SizedBox(height: spacing.spacing12),
          Text(
            'Responses are compared, adjusted, and\n'
            'optimized to reduce noise and improve\n'
            'clarity.',
            style: textTheme.bodyLarge?.copyWith(
              color: colors.text5.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomButton(
                text: 'Create Wallet',
                variant: ButtonVariant.translucent,
                onTap: () {
                  // TODO: Create wallet flow.
                },
              ),
              SizedBox(height: spacing.spacing12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push(RoutePaths.onboardingImportWallet),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: spacing.spacing4),
                  child: Center(
                    child: Text(
                      'Import Wallet',
                      style: textTheme.bodyLarge?.copyWith(
                        color: colors.text5.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../../shared/shared.dart';
import '../widgets/onboarding_import_wallet_word_page.dart';
import '../widgets/onboarding_welcome_header.dart';
import '../widgets/onboarding_welcome_mesh_background.dart';

/// Onboarding screen for importing a wallet via recovery phrase (UI only).
/// Full-bleed gradient; 4 words per carousel page, 1 per row; edge-to-edge PageView.
class OnboardingImportWalletScreen extends StatefulWidget {
  const OnboardingImportWalletScreen({super.key});

  @override
  State<OnboardingImportWalletScreen> createState() =>
      _OnboardingImportWalletScreenState();
}

class _OnboardingImportWalletScreenState
    extends State<OnboardingImportWalletScreen> {
  late final PageController _pageController;

  static const List<String?> _words = [
    'abandon',
    'wrong',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  ];

  static const List<bool?> _validationResults = [
    true,
    false,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const OnboardingWelcomeMeshBackground(),
          SafeArea(
            child: _ImportWalletContent(
              pageController: _pageController,
              words: _words,
              validationResults: _validationResults,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportWalletContent extends StatelessWidget {
  const _ImportWalletContent({
    required this.pageController,
    required this.words,
    required this.validationResults,
  });

  final PageController pageController;
  final List<String?> words;
  final List<bool?> validationResults;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final effects = context.effects;
    final type = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.xxl,
            spacing.xxl,
            spacing.xxl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OnboardingWelcomeHeader(),
              SizedBox(height: spacing.huge),
              Text('Import with recovery phrase', style: type.brandHero),
              SizedBox(height: spacing.md),
              Text(
                'Enter your 12-word recovery phrase in order. '
                'Each word goes in its own field.',
                style: type.brandBody.copyWith(
                  color: colors.onBrandArt.withValues(
                    alpha: effects.brandContentStrongOpacity,
                  ),
                ),
              ),
              SizedBox(height: spacing.xxxl),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: pageController,
            itemCount: 3,
            itemBuilder: (context, pageIndex) {
              final start = pageIndex * 4;
              return Center(
                child: OnboardingImportWalletWordPage(
                  words: words.sublist(start, start + 4).toList(),
                  validationResults: validationResults
                      .sublist(start, start + 4)
                      .toList(),
                  startNumber: start + 1,
                ),
              );
            },
          ),
        ),
        SizedBox(height: spacing.lg),
        Center(
          child: SmoothPageIndicator(
            controller: pageController,
            count: 3,
            effect: ExpandingDotsEffect(
              activeDotColor: colors.onBrandArt,
              dotColor: colors.onBrandArt.withValues(
                alpha: effects.brandIndicatorInactiveOpacity,
              ),
              dotHeight: spacing.sm,
              dotWidth: spacing.sm,
              expansionFactor: 4,
              spacing: spacing.sm,
            ),
          ),
        ),
        SizedBox(height: spacing.lg),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  'Never share your recovery phrase with anyone',
                  style: type.brandBody.copyWith(
                    color: colors.onBrandArt.withValues(
                      alpha: effects.brandContentSubtleOpacity,
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.xxxl),
              CustomButton(
                text: 'Continue',
                variant: ButtonVariant.translucent,
                onTap: () {
                  // TODO: Import wallet flow.
                },
              ),
              SizedBox(height: spacing.md),
              Semantics(
                button: true,
                label: 'Back',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.pop(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: spacing.xs),
                    child: Center(child: Text('Back', style: type.brandAction)),
                  ),
                ),
              ),
              SizedBox(height: spacing.xxl),
            ],
          ),
        ),
      ],
    );
  }
}

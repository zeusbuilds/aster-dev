import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';

/// Top header row for the onboarding welcome screen.
class OnboardingWelcomeHeader extends StatelessWidget {
  const OnboardingWelcomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SvgPicture.asset(
          'assets/brand/aster-logo.svg',
          width: spacing.iconLg,
          colorFilter: ColorFilter.mode(AsterColors.white, BlendMode.srcIn),
        ),
        SizedBox(width: spacing.sm),
        Text(
          'Aster',
          style: textTheme.headlineSmall?.copyWith(
            color: AsterColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

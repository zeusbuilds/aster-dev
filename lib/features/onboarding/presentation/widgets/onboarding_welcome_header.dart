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
    final colors = context.colors;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SvgPicture.asset(
          'assets/brand/aster-logo.svg',
          width: spacing.spacing36,
          colorFilter: ColorFilter.mode(colors.text5, BlendMode.srcIn),
        ),
        SizedBox(width: spacing.spacing8),
        Text(
          'Aster',
          style: textTheme.headlineSmall?.copyWith(
            color: colors.text5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

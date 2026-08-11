import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';

/// Top header row for the onboarding welcome screen.
class OnboardingWelcomeHeader extends StatelessWidget {
  const OnboardingWelcomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final icons = context.icons;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SvgPicture.asset(
          'assets/brand/aster-logo.svg',
          width: icons.lg,
          colorFilter: ColorFilter.mode(colors.onBrandArt, BlendMode.srcIn),
        ),
        SizedBox(width: context.spacing.sm),
        Text(
          'UTEXO',
          style: context.type.brandTitle.copyWith(color: colors.onBrandArt),
        ),
      ],
    );
  }
}

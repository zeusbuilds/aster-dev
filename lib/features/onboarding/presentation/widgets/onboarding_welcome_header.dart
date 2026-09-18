import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';

/// Shared onboarding wordmark, white only over the welcome artwork.
class OnboardingWelcomeHeader extends StatelessWidget {
  const OnboardingWelcomeHeader({super.key, this.onBrandArt = false});

  final bool onBrandArt;

  @override
  Widget build(BuildContext context) {
    final foreground = onBrandArt
        ? context.appColors.onBrandArt
        : context.colorScheme.onSurface;
    final art = context.art;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SvgPicture.asset(
          'assets/brand/aster-mark.svg',
          height: art.onboardingWordmarkMarkHeight,
          colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
        ),
        SizedBox(width: context.spacing.sm),
        Flexible(
          child: Text(
            'Aster',
            style: context.type.brandWordmark.copyWith(color: foreground),
          ),
        ),
      ],
    );
  }
}

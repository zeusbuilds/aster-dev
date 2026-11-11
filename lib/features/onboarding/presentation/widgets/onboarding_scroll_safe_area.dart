import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/layout/layout.dart';

/// Lets onboarding content scroll to the bottom edge on the Duo cover and
/// open landscape display. The final action owns the unobscured inset.
class OnboardingScrollSafeArea extends ConsumerWidget {
  const OnboardingScrollSafeArea({
    required this.builder,
    this.includeHorizontalInsets = true,
    super.key,
  });

  final Widget Function(bool scrollsInset, double scrollBottomInset) builder;
  final bool includeHorizontalInsets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDuoCover =
        ref
            .watch(duoCoverLayoutProvider)
            .value
            ?.appliesTo(MediaQuery.sizeOf(context)) ==
        true;
    final scrollsBottomInset = isDuoCover || context.isOpenDuoLandscape;
    return SafeArea(
      left: includeHorizontalInsets,
      right: includeHorizontalInsets,
      bottom: !scrollsBottomInset,
      child: builder(
        scrollsBottomInset,
        scrollsBottomInset ? context.windowInsets.bottomSafe : 0,
      ),
    );
  }
}

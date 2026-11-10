import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/layout/layout.dart';

/// Lets scrolling onboarding content run to the bottom edge on the Duo cover.
/// Its final action owns the unobscured inset so it scrolls with the content.
class OnboardingScrollSafeArea extends ConsumerWidget {
  const OnboardingScrollSafeArea({required this.builder, super.key});

  final Widget Function(bool isDuoCover, double scrollBottomInset) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDuoCover =
        ref
            .watch(duoCoverLayoutProvider)
            .value
            ?.appliesTo(MediaQuery.sizeOf(context)) ==
        true;
    return SafeArea(
      bottom: !isDuoCover,
      child: builder(
        isDuoCover,
        isDuoCover ? MediaQuery.paddingOf(context).bottom : 0,
      ),
    );
  }
}

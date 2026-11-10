import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'duo_display_layout.dart';

/// Applies window insets to the content of a centered modal sheet.
class AsterSheetSafeArea extends ConsumerWidget {
  const AsterSheetSafeArea({
    super.key,
    required this.child,
    this.bottom = false,
    this.minimum = EdgeInsets.zero,
  });

  final Widget child;
  final bool bottom;
  final EdgeInsets minimum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safeArea = SafeArea(
      top: false,
      bottom: bottom,
      minimum: minimum,
      child: child,
    );
    final layout = ref.watch(duoDisplayLayoutProvider).value;
    final media = MediaQuery.of(context);
    if (layout == null || layout.isCover || !layout.appliesTo(media.size)) {
      return safeArea;
    }

    // A display feature can make the modal center itself in a sub-screen.
    // In that case, keep the insets Flutter already calculated for that region.
    final viewMedia = MediaQueryData.fromView(View.of(context));
    if (DisplayFeatureSubScreen.avoidBounds(viewMedia).isNotEmpty) {
      return safeArea;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Material centers its width-constrained sheet. Its outside margin
        // already covers some or all of the window's horizontal safe area.
        final margin = math.max(
          0.0,
          (media.size.width - constraints.maxWidth) / 2,
        );
        if (margin == 0) return safeArea;
        EdgeInsets remaining(EdgeInsets insets) => insets.copyWith(
          left: math.max(0.0, insets.left - margin),
          right: math.max(0.0, insets.right - margin),
        );
        return MediaQuery(
          data: media.copyWith(
            padding: remaining(media.padding),
            viewPadding: remaining(media.viewPadding),
            viewInsets: remaining(media.viewInsets),
          ),
          child: safeArea,
        );
      },
    );
  }
}

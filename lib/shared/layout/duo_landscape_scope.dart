import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme.dart';
import 'duo_display_layout.dart';

/// Provides a single top margin for open Duo landscape content and app bars.
/// Its wrappers stay mounted as the device folds so the navigator keeps state.
class AsterDuoLandscapeScope extends ConsumerWidget {
  const AsterDuoLandscapeScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final isLandscape =
        ref
            .watch(duoDisplayLayoutProvider)
            .value
            ?.isOpenLandscapeFor(media.size) ==
        true;
    final top = math.max(media.viewPadding.top, context.spacing.md);
    return _DuoLandscape(
      active: isLandscape,
      child: MediaQuery(
        data: isLandscape
            ? media.copyWith(
                viewPadding: media.viewPadding.copyWith(top: top),
                padding: media.padding.copyWith(
                  top: math.max(media.padding.top, top - media.viewInsets.top),
                ),
              )
            : media,
        child: child,
      ),
    );
  }
}

class _DuoLandscape extends InheritedWidget {
  const _DuoLandscape({required this.active, required super.child});

  final bool active;

  @override
  bool updateShouldNotify(_DuoLandscape oldWidget) =>
      active != oldWidget.active;
}

extension AsterDuoLandscapeContext on BuildContext {
  /// Whether the current native Duo inner window is wider than it is tall.
  bool get isOpenDuoLandscape =>
      dependOnInheritedWidgetOfExactType<_DuoLandscape>()?.active == true;

  /// Both equal-width panes must fit a compact phone layout inside their
  /// respective horizontal system insets.
  bool get fitsDuoLandscapePanes {
    if (!isOpenDuoLandscape) return false;
    const minimumPaneWidth = 320.0;
    final insets = MediaQuery.viewPaddingOf(this);
    return MediaQuery.sizeOf(this).width / 2 -
            math.max(insets.left, insets.right) >=
        minimumPaneWidth;
  }
}

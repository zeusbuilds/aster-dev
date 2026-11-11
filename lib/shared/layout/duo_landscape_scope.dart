import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme.dart';
import 'duo_display_layout.dart';

/// Provides the top margin and action width for open Duo landscape.
/// Its wrappers stay mounted as the device folds so the navigator keeps state.
class AsterDuoLandscapeScope extends ConsumerWidget {
  const AsterDuoLandscapeScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final spacing = context.spacing;
    final layout = ref.watch(duoDisplayLayoutProvider).value;
    final actionMaxWidth = layout?.actionMaxWidthFor(media.size, spacing.xxl);
    final top = math.max(media.viewPadding.top, spacing.md);
    return _DuoLandscape(
      actionMaxWidth: actionMaxWidth,
      layout: actionMaxWidth == null ? null : layout,
      child: MediaQuery(
        data: actionMaxWidth != null
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
  const _DuoLandscape({
    required this.actionMaxWidth,
    required this.layout,
    required super.child,
  });

  final double? actionMaxWidth;
  final DuoDisplayLayout? layout;

  @override
  bool updateShouldNotify(_DuoLandscape oldWidget) =>
      actionMaxWidth != oldWidget.actionMaxWidth ||
      layout?.railBand != oldWidget.layout?.railBand;
}

extension AsterDuoLandscapeContext on BuildContext {
  /// Whether the current native Duo inner window is wider than it is tall.
  bool get isOpenDuoLandscape => duoLandscapeActionMaxWidth != null;

  /// The landscape action width before individual pane or sheet constraints.
  double? get duoLandscapeActionMaxWidth =>
      dependOnInheritedWidgetOfExactType<_DuoLandscape>()?.actionMaxWidth;

  DuoDisplayLayout? get duoLandscapeLayout =>
      dependOnInheritedWidgetOfExactType<_DuoLandscape>()?.layout;

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

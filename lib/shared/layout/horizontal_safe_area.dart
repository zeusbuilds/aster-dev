import 'package:flutter/widgets.dart';

/// Keeps screen content clear of side-mounted system UI, including the
/// iPhone Duo cover display. The enclosing scaffold still paints edge to edge.
///
/// The screen owns vertical spacing: a pinned action and a scrolling list
/// may apply the bottom inset in different places.
class AsterHorizontalSafeArea extends StatelessWidget {
  const AsterHorizontalSafeArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SafeArea(top: false, bottom: false, child: child);
}

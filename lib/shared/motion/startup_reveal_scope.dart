import 'package:flutter/widgets.dart';

/// Signals when the launch overlay has finished revealing the app underneath.
class StartupRevealScope extends InheritedNotifier<ValueNotifier<bool>> {
  const StartupRevealScope({
    super.key,
    required ValueNotifier<bool> splashVisible,
    required super.child,
  }) : super(notifier: splashVisible);

  static bool splashVisibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<StartupRevealScope>()
          ?.notifier
          ?.value ??
      false;
}
